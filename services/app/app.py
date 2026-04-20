from pathlib import Path

from flask import Flask, abort, send_from_directory


current_dir = Path(__file__).resolve().parent
app = Flask(__name__)

portfolio_dist_dir = Path("/app/vite/dist")

for base in [current_dir, *current_dir.parents]:
    candidate = base / "services" / "app" / "vite" / "dist"
    if candidate.exists():
        portfolio_dist_dir = candidate
        break


@app.route("/favicon.ico", defaults={"filename": "favicon.ico"})
def vite_root_static_file(filename):
    if filename != "favicon.ico" or not portfolio_dist_dir.exists():
        abort(404)
    return send_from_directory(portfolio_dist_dir, filename)


@app.route("/")
def home():
    return serve_vite_portfolio_app()


@app.route("/assets/<path:filename>")
def vite_assets(filename):
    assets_dir = portfolio_dist_dir / "assets"
    if not assets_dir.exists():
        abort(404)
    return send_from_directory(assets_dir, filename)


@app.route("/vite-app/<path:filename>")
def vite_misc_files(filename):
    if not portfolio_dist_dir.exists():
        abort(404)
    return send_from_directory(portfolio_dist_dir, filename)


@app.route("/games/")
def games():
    return serve_vite_portfolio_app()


@app.route("/siddharth/")
def siddharth_home():
    return serve_vite_portfolio_app()


@app.route("/shivam/")
def shivam_home():
    return serve_vite_portfolio_app()


@app.route("/suryan/")
def suryan_home():
    return serve_vite_portfolio_app()


@app.route("/nivi/")
def nivi_home():
    return serve_vite_portfolio_app()


def serve_vite_portfolio_app():
    index_file = portfolio_dist_dir / "index.html"
    if index_file.exists():
        return send_from_directory(portfolio_dist_dir, "index.html")

    return (
        "Vite build not found. Run 'npm install && npm run build' in services/app/vite.",
        503,
    )


if __name__ == "__main__":
    app.run(debug=True)
