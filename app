[app.py](https://github.com/user-attachments/files/26929315/app.py)
from flask import Flask, render_template, request, jsonify, Response
from outscraper import ApiClient
import csv, io, re, time, json
from datetime import datetime

try:
    import phonenumbers
    from phonenumbers import format_number, PhoneNumberFormat
    PHONENUMBERS_AVAILABLE = True
except ImportError:
    PHONENUMBERS_AVAILABLE = False

app = Flask(__name__)

API_KEY = "NDc2MTM0NTlhZGZhNGQzNWFhNGVhY2UwZDFjMTllMTh8MjQ0NjdiYTZlYw"

INDUSTRIES = {
    "restaurant":"restaurant","cafe":"cafe coffee shop","bar":"bar pub",
    "fastfood":"fast food","bakery":"bakery","gym":"gym fitness center",
    "hospital":"hospital","clinic":"medical clinic","dental":"dental clinic",
    "pharmacy":"pharmacy drugstore","spa":"spa wellness center","bank":"bank",
    "insurance":"insurance agency","accounting":"accounting firm CPA",
    "law":"law firm lawyer","realestate":"real estate agency",
    "supermarket":"supermarket grocery","mall":"shopping mall",
    "clothing":"clothing store","electronics":"electronics store",
    "hardware":"hardware store","hotel":"hotel","salon":"hair salon beauty",
    "carwash":"car wash","auto":"auto repair mechanic","school":"school",
    "university":"university college","church":"church",
    "logistics":"logistics courier","it":"IT company software",
    "marketing":"marketing agency","construction":"construction company",
    "vape":"vape shop","laundry":"laundry shop","printing":"printing shop",
}

CITIES_BY_REGION = {
    "Philippines":["Manila","Quezon City","Cebu City","Davao City","Makati","Pasig","Taguig","Mandaluyong","Pasay","Paranaque","Las Pinas","Muntinlupa","Marikina","Caloocan","Valenzuela","Zamboanga","Cagayan de Oro","General Santos","Bacolod","Iloilo City","Baguio","Antipolo","Lipa City","Dumaguete","Tacloban"],
    "USA":["New York City","Los Angeles","Chicago","Houston","Phoenix","Philadelphia","San Antonio","San Diego","Dallas","San Jose","Austin","San Francisco","Seattle","Denver","Miami","Atlanta","Boston","Las Vegas","Nashville","Portland"],
    "UK":["London","Birmingham","Manchester","Leeds","Glasgow","Liverpool","Edinburgh","Bristol"],
    "Australia":["Sydney","Melbourne","Brisbane","Perth","Adelaide","Gold Coast","Canberra"],
    "Canada":["Toronto","Montreal","Vancouver","Calgary","Edmonton","Ottawa","Winnipeg"],
    "UAE":["Dubai","Abu Dhabi","Sharjah","Ajman","Ras Al Khaimah"],
    "Singapore":["Singapore"],
    "Malaysia":["Kuala Lumpur","Penang","Johor Bahru","Kota Kinabalu","Ipoh"],
    "Indonesia":["Jakarta","Surabaya","Bandung","Medan","Makassar"],
    "India":["Mumbai","Delhi","Bangalore","Hyderabad","Chennai","Kolkata","Pune","Ahmedabad"],
    "Japan":["Tokyo","Osaka","Yokohama","Nagoya","Sapporo","Kyoto","Fukuoka"],
    "South Korea":["Seoul","Busan","Incheon","Daegu","Daejeon"],
    "China":["Beijing","Shanghai","Guangzhou","Shenzhen","Chengdu"],
    "Europe":["Paris France","Berlin Germany","Madrid Spain","Rome Italy","Amsterdam Netherlands","Vienna Austria","Stockholm Sweden","Lisbon Portugal","Athens Greece","Warsaw Poland"],
    "Middle East":["Riyadh Saudi Arabia","Jeddah Saudi Arabia","Doha Qatar","Kuwait City Kuwait","Cairo Egypt"],
    "Africa":["Lagos Nigeria","Nairobi Kenya","Johannesburg South Africa","Cape Town South Africa","Accra Ghana"],
    "Latin America":["Sao Paulo Brazil","Rio de Janeiro Brazil","Buenos Aires Argentina","Bogota Colombia","Lima Peru","Mexico City Mexico"],
}

COUNTRY_CODES = {
    "PHILIPPINES":"PH","MANILA":"PH","CEBU":"PH","DAVAO":"PH","QUEZON":"PH",
    "USA":"US","NEW YORK":"US","LOS ANGELES":"US","CHICAGO":"US",
    "UK":"GB","LONDON":"GB","MANCHESTER":"GB",
    "AUSTRALIA":"AU","SYDNEY":"AU","MELBOURNE":"AU",
    "CANADA":"CA","TORONTO":"CA","VANCOUVER":"CA",
    "INDIA":"IN","MUMBAI":"IN","DELHI":"IN",
    "JAPAN":"JP","TOKYO":"JP","OSAKA":"JP",
    "SOUTH KOREA":"KR","SEOUL":"KR",
    "CHINA":"CN","BEIJING":"CN","SHANGHAI":"CN",
    "SINGAPORE":"SG","MALAYSIA":"MY","KUALA LUMPUR":"MY",
    "INDONESIA":"ID","JAKARTA":"ID",
    "UAE":"AE","DUBAI":"AE","ABU DHABI":"AE",
    "GERMANY":"DE","FRANCE":"FR","PARIS":"FR",
    "SPAIN":"ES","ITALY":"IT","BRAZIL":"BR","MEXICO":"MX",
    "NIGERIA":"NG","KENYA":"KE","SOUTH AFRICA":"ZA","EGYPT":"EG",
    "SAUDI ARABIA":"SA","QATAR":"QA",
}

def get_cc(loc):
    loc_up = loc.upper()
    for k, v in COUNTRY_CODES.items():
        if k in loc_up:
            return v
    return None

def fix_phone(raw, cc=None):
    if not raw:
        return ""
    phone = re.sub(r'[^\d\+\-\(\)\s\.]', '', str(raw)).strip()
    if not phone or phone in ["-",".","+",""]:
        return ""
    if PHONENUMBERS_AVAILABLE:
        for attempt in [phone, ("+" + re.sub(r'\D','',phone)) if not phone.startswith("+") else None]:
            if not attempt:
                continue
            for c in [cc, None]:
                try:
                    parsed = phonenumbers.parse(attempt, c)
                    if phonenumbers.is_valid_number(parsed):
                        return format_number(parsed, PhoneNumberFormat.INTERNATIONAL)
                except:
                    pass
    digits = re.sub(r'\D','',phone)
    if phone.startswith("+") and len(digits) >= 7:
        return phone
    if digits.startswith("09") and len(digits) == 11:
        return f"+63 {digits[1:4]} {digits[4:7]} {digits[7:]}"
    if len(digits) == 10 and cc in ["US","CA"]:
        return f"+1 ({digits[0:3]}) {digits[3:6]}-{digits[6:]}"
    return phone

def scrape_location(client, query, location, limit):
    cc = get_cc(location)
    try:
        results = client.google_maps_search(
            f"{query} {location}", limit=limit, language="en",
            fields=["name","full_address","phone","site","rating",
                    "street","city","state","country_code","postal_code",
                    "type","subtypes","emails_and_contacts"]
        )
        businesses = []
        if results and results[0]:
            for place in results[0]:
                addr = place.get("full_address") or ""
                if not addr:
                    parts = [place.get("street",""),place.get("city",""),
                             place.get("state",""),place.get("postal_code",""),
                             place.get("country_code","")]
                    addr = ", ".join(p for p in parts if p)
                phone_cc = place.get("country_code") or cc
                phone = fix_phone(place.get("phone"), phone_cc)
                email = ""
                contacts = place.get("emails_and_contacts") or {}
                if isinstance(contacts, dict):
                    el = contacts.get("emails", [])
                    if el: email = el[0]
                businesses.append({
                    "name": (place.get("name") or "").strip(),
                    "address": addr.strip(),
                    "phone": phone,
                    "website": (place.get("site") or "").strip(),
                    "email": email,
                    "rating": str(place.get("rating") or ""),
                    "category": (place.get("subtypes") or place.get("type") or ""),
                    "country": (place.get("country_code") or cc or ""),
                    "location_searched": location,
                })
        return businesses
    except Exception as e:
        return []

@app.route("/")
def index():
    return render_template("index.html",
        industries=sorted(INDUSTRIES.keys()),
        regions=sorted(CITIES_BY_REGION.keys()),
        cities_by_region=CITIES_BY_REGION)

@app.route("/get_cities")
def get_cities():
    region = request.args.get("region","")
    cities = CITIES_BY_REGION.get(region, [])
    return jsonify(cities)

@app.route("/scrape", methods=["POST"])
def scrape():
    data = request.json
    industry_key  = data.get("industry","gym")
    custom_query  = data.get("custom_query","").strip()
    region        = data.get("region","")
    selected_city = data.get("city","").strip()
    custom_city   = data.get("custom_city","").strip()
    limit         = int(data.get("limit", 20))
    max_total     = int(data.get("max_total", 500))
    fetch_emails  = data.get("fetch_emails", True)

    query = custom_query if custom_query else INDUSTRIES.get(industry_key, industry_key)

    # Build city list
    if custom_city:
        cities = [custom_city]
    elif selected_city:
        cities = [f"{selected_city}, {region}" if region and region not in selected_city else selected_city]
    elif region == "All Regions":
        cities = []
        for cc_list in CITIES_BY_REGION.values():
            cities.extend(cc_list)
    elif region in CITIES_BY_REGION:
        cities = [f"{c}, {region}" for c in CITIES_BY_REGION[region]]
    else:
        return jsonify({"error": "No location selected"}), 400

    client = ApiClient(api_key=API_KEY)
    all_results = []
    seen = set()
    total = 0

    for city in cities:
        if max_total > 0 and total >= max_total:
            break
        batch_limit = min(limit, max_total - total) if max_total > 0 else limit
        batch = scrape_location(client, query, city, batch_limit)
        for b in batch:
            key = (b["name"].lower().strip(), b["phone"].strip())
            if key not in seen:
                seen.add(key)
                all_results.append(b)
                total += 1
        time.sleep(1)

    # Enrich emails
    if fetch_emails:
        missing_sites = list({b["website"] for b in all_results if not b["email"] and b["website"]})
        if missing_sites:
            try:
                email_results = client.emails_and_contacts(missing_sites)
                email_map = {}
                if email_results:
                    for item in email_results:
                        site = item.get("query","")
                        emails = item.get("emails",[])
                        if emails: email_map[site] = emails[0]
                for b in all_results:
                    if not b["email"] and b["website"] in email_map:
                        b["email"] = email_map[b["website"]]
            except:
                pass

    return jsonify({"results": all_results, "total": len(all_results)})

@app.route("/export")
def export():
    import json as _json
    raw = request.args.get("data","[]")
    results = _json.loads(raw)
    output = io.StringIO()
    fields = ["name","phone","email","address","website","rating","category","country","location_searched"]
    writer = csv.DictWriter(output, fieldnames=fields, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(results)
    output.seek(0)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return Response(
        output.getvalue(),
        mimetype="text/csv",
        headers={"Content-Disposition": f"attachment;filename=scraper_{timestamp}.csv"}
    )

if __name__ == "__main__":
    app.run(debug=False, host="0.0.0.0", port=5000)
