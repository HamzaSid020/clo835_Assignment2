from flask import Flask, render_template, request
from pymysql import connections
import os
import random
import argparse
import time

app = Flask(__name__)

DBHOST = os.environ.get("DBHOST", "mysql-service.mysql-ns.svc.cluster.local")
DBUSER = os.environ.get("DBUSER", "root")
DBPWD = os.environ.get("DBPWD", "rootpassword")
DATABASE = os.environ.get("DATABASE", "employees")
COLOR_FROM_ENV = os.environ.get('APP_COLOR', "lime")
DBPORT = int(os.environ.get("DBPORT", 3306))

# Retry logic for DB connection
def connect_db():
    for _ in range(5):  # Retry 5 times
        try:
            return connections.Connection(
                host=DBHOST,
                port=DBPORT,
                user=DBUSER,
                password=DBPWD,
                db=DATABASE
            )
        except Exception as e:
            print(f"DB connection failed: {e}. Retrying in 5 seconds...")
            time.sleep(5)
    raise Exception("Failed to connect to MySQL after retries")

db_conn = connect_db()
table = 'employee'

color_codes = {
    "red": "#e74c3c",
    "green": "#16a085",
    "blue": "#89CFF0",
    "blue2": "#30336b",
    "pink": "#f4c2c2",
    "darkblue": "#130f40",
    "lime": "#C1FF9C",
}

SUPPORTED_COLORS = ",".join(color_codes.keys())
COLOR = random.choice(["red", "green", "blue", "blue2", "darkblue", "pink", "lime"])

@app.route("/", methods=['GET', 'POST'])
def home():
    return render_template('addemp.html', color=color_codes[COLOR])

@app.route("/about", methods=['GET', 'POST'])
def about():
    return render_template('about.html', color=color_codes[COLOR])
    
@app.route("/addemp", methods=['POST'])
def AddEmp():
    emp_id = request.form['emp_id']
    first_name = request.form['first_name']
    last_name = request.form['last_name']
    primary_skill = request.form['primary_skill']
    location = request.form['location']

    insert_sql = "INSERT INTO employee VALUES (%s, %s, %s, %s, %s)"
    cursor = db_conn.cursor()
    try:
        cursor.execute(insert_sql, (emp_id, first_name, last_name, primary_skill, location))
        db_conn.commit()
        emp_name = f"{first_name} {last_name}"
    except Exception as e:
        print(f"Error: {e}")
    finally:
        cursor.close()

    return render_template('addempoutput.html', name=emp_name, color=color_codes[COLOR])

@app.route("/getemp", methods=['GET', 'POST'])
def GetEmp():
    return render_template("getemp.html", color=color_codes[COLOR])

@app.route("/fetchdata", methods=['GET', 'POST'])
def FetchData():
    emp_id = request.form['emp_id']
    select_sql = "SELECT emp_id, first_name, last_name, primary_skill, location FROM employee WHERE emp_id=%s"
    cursor = db_conn.cursor()
    try:
        cursor.execute(select_sql, (emp_id,))
        result = cursor.fetchone()
        if result:
            output = {
                "emp_id": result[0],
                "first_name": result[1],
                "last_name": result[2],
                "primary_skills": result[3],
                "location": result[4]
            }
        else:
            output = {"emp_id": emp_id, "first_name": "N/A", "last_name": "N/A", "primary_skills": "N/A", "location": "N/A"}
    except Exception as e:
        print(f"Error: {e}")
        output = {"emp_id": emp_id, "first_name": "Error", "last_name": "", "primary_skills": "", "location": ""}
    finally:
        cursor.close()

    return render_template("getempoutput.html", id=output["emp_id"], fname=output["first_name"],
                          lname=output["last_name"], interest=output["primary_skills"], location=output["location"], color=color_codes[COLOR])

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--color', required=False)
    args = parser.parse_args()

    if args.color:
        COLOR = args.color
        if COLOR_FROM_ENV:
            print(f"Color from env ({COLOR_FROM_ENV}) overridden by CLI: {COLOR}")
    elif COLOR_FROM_ENV:
        COLOR = COLOR_FROM_ENV
        print(f"Color from env: {COLOR}")
    else:
        print(f"Random color: {COLOR}")

    if COLOR not in color_codes:
        print(f"Color '{COLOR}' not supported. Expected: {SUPPORTED_COLORS}")
        exit(1)

    app.run(host='0.0.0.0', port=80, debug=True)