from flask import Flask
import os
import pymysql

app = Flask(__name__)


@app.route("/")
def home():
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>IT Infrastructure and DevOps assignment</title>
    </head>
    <body>
        <h1>Techkraft</h1>
        <p>Nginx reverse proxy is forwarding requests to Flask.</p>
        <p>Application status: Running</p>
        <p>Database: MySQL</p>
    </body>
    </html>
    """


@app.route("/health")
def health():
    return {
        "status": "healthy",
        "application": "Flask",
        "database": "MySQL"
    }


@app.route("/db")
def database():
    try:
        conn = pymysql.connect(
            host=os.getenv("DB_HOST", "db"),
            port=int(os.getenv("DB_PORT", "3306")),
            database=os.getenv("DB_NAME", "devopsdb"),
            user=os.getenv("DB_USER", "devops"),
            password=os.getenv("DB_PASSWORD", "devopspass")
        )

        cursor = conn.cursor()
        cursor.execute("SELECT VERSION()")
        version = cursor.fetchone()[0]

        cursor.close()
        conn.close()

        return {
            "database": "connected",
            "mysql_version": version
        }

    except Exception as e:
        return {
            "database": "error",
            "message": str(e)
        }, 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
