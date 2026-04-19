from pathlib import Path

from flask import Flask, redirect, render_template, url_for


# Support shared templates both from local source checkout and container image.
current_dir = Path(__file__).resolve().parent
template_dir = Path("/app/templates")

for base in [current_dir, *current_dir.parents]:
    candidate = base / "templates"
    if candidate.exists():
        template_dir = candidate
        break

app = Flask(__name__, template_folder=str(template_dir))


@app.route("/")
def home():
    return render_template("home/index.html")


@app.route("/work/")
def work():
    return render_template("portfolios/work.html")


@app.route("/viz/")
def viz():
    return render_template("portfolios/viz.html")


@app.route("/about/")
def about():
    return render_template("portfolios/about.html")


@app.route("/games/")
def games():
    return render_template("games/index.html")


@app.route("/siddharth/")
def siddharth_home():
    return redirect(url_for("work"))


@app.route("/shivam/")
def shivam_home():
    return redirect(url_for("games"))


@app.route("/suryan/")
def suryan_home():
    return redirect(url_for("viz"))


@app.route("/nivi/")
def nivi_home():
    return redirect(url_for("about"))


if __name__ == "__main__":
    app.run(debug=True)
