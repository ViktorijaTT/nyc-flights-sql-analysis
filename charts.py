"""Draw the three result charts and the ER diagram.

Run after export_results.py has written the CSV files in results/:

    python charts.py

Output (PNG, 150 dpi) in images/:
    chart1_hour_of_day_on_time.png
    chart2_monthly_cancellations.png
    chart3_weather_arrival_delay.png
    er_diagram.png

Every number in the chart titles is read from results/*.csv, so the charts
cannot drift away from the query results.
"""
from pathlib import Path

import matplotlib

matplotlib.use("Agg")                     # save files only; no window needed
import matplotlib.pyplot as plt           # noqa: E402
import pandas as pd                       # noqa: E402
from matplotlib.patches import FancyBboxPatch  # noqa: E402

PROJECT_DIR = Path(__file__).resolve().parent
RESULTS_DIR = PROJECT_DIR / "results"
IMAGES_DIR = PROJECT_DIR / "images"
IMAGES_DIR.mkdir(exist_ok=True)
DPI = 150


def chart_hour_of_day() -> None:
    """Line chart: on-time and cancellation rates by scheduled departure hour (q07)."""
    df = pd.read_csv(RESULTS_DIR / "q07_hour_of_day_delays.csv")
    best = df.loc[df["on_time_rate_pct"].idxmax()]     # hour with the highest on-time rate
    worst = df.loc[df["on_time_rate_pct"].idxmin()]    # hour with the lowest on-time rate

    fig, ax = plt.subplots(figsize=(10, 5.6))
    ax.plot(df["sched_dep_hour"], df["on_time_rate_pct"], marker="o", color="#1f5f8b",
            label="On-time rate (%)")
    ax.plot(df["sched_dep_hour"], df["cancellation_rate_pct"], marker="s", color="#c0392b",
            label="Cancellation rate (%)")
    ax.set_xlabel("Scheduled departure hour (local New York time)")
    ax.set_ylabel("Percent of flights")
    ax.set_ylim(0, 100)                                       # rates run from 0 to 100
    ax.set_xticks(df["sched_dep_hour"])
    ax.grid(alpha=0.3)
    ax.legend(loc="center left")
    ax.set_title(
        f"On-time rate falls later in the day: {best['on_time_rate_pct']:.2f}% at "
        f"{int(best['sched_dep_hour']):02d}:00, {worst['on_time_rate_pct']:.2f}% at "
        f"{int(worst['sched_dep_hour']):02d}:00\n"
        "(on time = arrival delay under 15 minutes; completed flights; 2023, JFK, LGA, EWR)",
        fontsize=11, loc="left")
    fig.tight_layout()
    fig.savefig(IMAGES_DIR / "chart1_hour_of_day_on_time.png", dpi=DPI)
    plt.close(fig)


def chart_monthly_cancellations() -> None:
    """Bar chart: cancellation rate by month (q04)."""
    df = pd.read_csv(RESULTS_DIR / "q04_monthly_trend_month_over_month.csv")
    df["month_date"] = pd.to_datetime(df["month_label"] + "-01")
    df["month_name"] = df["month_date"].dt.strftime("%b")
    peak = df.loc[df["cancellation_rate_pct"].idxmax()]
    low = df.loc[df["cancellation_rate_pct"].idxmin()]

    fig, ax = plt.subplots(figsize=(10, 5.6))
    colors = ["#c0392b" if m == peak["month_label"] else "#7f8c8d" for m in df["month_label"]]
    bars = ax.bar(df["month_name"], df["cancellation_rate_pct"], color=colors)
    ax.bar_label(bars, fmt="%.2f%%", fontsize=9, padding=2)   # value on top of each bar
    ax.set_xlabel("Month of scheduled departure (2023)")
    ax.set_ylabel("Cancelled flights (% of scheduled)")
    ax.set_ylim(0, df["cancellation_rate_pct"].max() * 1.15)
    ax.grid(axis="y", alpha=0.3)
    ax.set_axisbelow(True)                                     # gridlines behind the bars
    ax.set_title(
        f"Cancellations peaked in {peak['month_date'].strftime('%B')} 2023 at "
        f"{peak['cancellation_rate_pct']:.2f}% of scheduled flights\n"
        f"The lowest month was {low['month_date'].strftime('%B')} at "
        f"{low['cancellation_rate_pct']:.2f}%",
        fontsize=11, loc="left")
    fig.tight_layout()
    fig.savefig(IMAGES_DIR / "chart2_monthly_cancellations.png", dpi=DPI)
    plt.close(fig)


def chart_weather() -> None:
    """Horizontal bar chart: average arrival delay by weather group (q08)."""
    df = pd.read_csv(RESULTS_DIR / "q08_weather_conditions_and_delays.csv")
    df = df.sort_values("avg_arr_delay_min")                  # smallest at the bottom
    rain = df[df["weather_group"].str.startswith("Rain")].iloc[0]
    clear = df[df["weather_group"].str.startswith("Clear")].iloc[0]

    fig, ax = plt.subplots(figsize=(10, 5.6))
    colors = ["#c0392b" if g.startswith("Rain") else "#1f5f8b" if g.startswith("Clear")
              else "#7f8c8d" for g in df["weather_group"]]
    bars = ax.barh(df["weather_group"], df["avg_arr_delay_min"], color=colors)
    labels = [f"{v:.2f} min  (on time {o:.2f}%, {n:,} flights)"
              for v, o, n in zip(df["avg_arr_delay_min"], df["on_time_rate_pct"],
                                 df["scheduled_flights"])]
    ax.bar_label(bars, labels=labels, padding=4, fontsize=9)
    ax.set_xlabel("Average arrival delay in minutes (completed flights)")
    ax.set_xlim(0, df["avg_arr_delay_min"].max() * 2.1)      # room for the labels
    ax.grid(axis="x", alpha=0.3)
    ax.set_axisbelow(True)
    ax.set_title(
        f"Rainy departure hours average a {rain['avg_arr_delay_min']:.2f}-minute arrival delay, "
        f"against {clear['avg_arr_delay_min']:.2f} in clear hours\n"
        "(association only; weather timestamps have an unconfirmed time zone)",
        fontsize=11, loc="left")
    fig.tight_layout()
    fig.savefig(IMAGES_DIR / "chart3_weather_arrival_delay.png", dpi=DPI)
    plt.close(fig)


def draw_er_diagram() -> None:
    """Entity-relationship diagram of the five tables, drawn with matplotlib boxes and lines."""
    fig, ax = plt.subplots(figsize=(14, 10))
    ax.set_xlim(0, 16)
    ax.set_ylim(0, 11)                 # extra room at the top for the title
    ax.axis("off")

    def table_box(x, y, w, h, title, lines, color):
        """Draw a rounded box with a coloured title bar and the key columns below it."""
        ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.05",
                                    facecolor="white", edgecolor=color, linewidth=2))
        ax.add_patch(FancyBboxPatch((x, y + h - 0.6), w, 0.6, boxstyle="round,pad=0.05",
                                    facecolor=color, edgecolor=color, linewidth=2))
        ax.text(x + w / 2, y + h - 0.3, title, ha="center", va="center",
                color="white", fontsize=11, fontweight="bold")
        for i, line in enumerate(lines):
            ax.text(x + 0.2, y + h - 0.95 - i * 0.37, line, ha="left", va="center",
                    fontsize=8.6, family="monospace")

    def relation(x1, y1, x2, y2, label_lines, label_xy, dashed=False):
        """Line between two tables plus a short label. Dashed = no foreign key in MySQL."""
        ax.plot([x1, x2], [y1, y2], color="#34495e", linewidth=1.6,
                linestyle="--" if dashed else "-", zorder=0)
        ax.text(label_xy[0], label_xy[1], "\n".join(label_lines), ha="center", va="center",
                fontsize=8, color="#34495e")

    # Table positions (x, y, width, height) in diagram units. Gaps leave room for labels.
    airlines_box = (0.3, 7.2, 3.6, 2.5)
    planes_box = (0.3, 0.6, 3.6, 2.4)
    flights_box = (6.0, 0.5, 4.4, 6.6)
    airports_box = (12.1, 6.6, 3.6, 2.9)
    weather_box = (12.1, 0.6, 3.6, 3.0)

    table_box(*airlines_box, "airlines  (14 rows)",
              ["carrier        PK", "airline_name"], "#2e86c1")
    table_box(*airports_box, "airports  (1,255 rows)",
              ["faa            PK", "airport_name", "lat, lon, alt_ft", "tzone"], "#16a085")
    table_box(*flights_box, "flights  (435,352 rows)",
              ["flight_id      PK", "flight_date", "carrier      FK",
               "origin       FK", "dest         FK", "tailnum      (no FK)",
               "flight_status", "sched_dep_datetime", "dep_delay_min",
               "arr_delay_min", "time_hour     (weather key)"], "#8e44ad")
    table_box(*planes_box, "planes  (4,840 rows)",
              ["tailnum        PK", "year_manufactured", "manufacturer", "model, engines, seats"],
              "#d35400")
    table_box(*weather_box, "weather  (26,207 rows)",
              ["origin         PK (1 of 2)", "time_hour      PK (2 of 2)",
               "temp_f, dewpoint_f", "visibility_miles", "precip_in", "wind_speed_mph"],
              "#7f8c8d")

    # Relationships. Solid = foreign key in MySQL; dashed = joined in queries, no foreign key.
    relation(3.9, 8.45, 6.0, 6.9, ["carrier", "many : 1"], (4.95, 8.0))
    relation(12.1, 7.6, 10.4, 6.3, ["origin, dest", "many : 1"], (11.25, 7.25))
    relation(13.9, 3.6, 13.9, 6.6, ["origin", "many : 1"], (14.9, 5.1))
    relation(3.9, 2.0, 6.0, 2.0, ["tailnum", "(no FK)"], (4.95, 2.45), dashed=True)
    relation(10.4, 2.0, 12.1, 2.0, ["origin + time_hour", "(no FK)"], (11.25, 2.45), dashed=True)

    ax.text(8.0, 10.65, "NYC flights 2023: five tables and how they link", ha="center",
            fontsize=14, fontweight="bold")
    ax.text(8.0, 10.25, "Solid lines: foreign keys defined in MySQL.   Dashed lines: links used "
            "in queries but not enforced (see README).", ha="center", fontsize=9,
            color="#34495e")
    ax.text(0.3, 0.1, "PK = primary key; FK = foreign key (enforced).  Flights join to weather "
            "on origin and time_hour.", fontsize=8, color="#34495e")

    fig.tight_layout()
    fig.savefig(IMAGES_DIR / "er_diagram.png", dpi=DPI)
    plt.close(fig)


if __name__ == "__main__":
    chart_hour_of_day()
    chart_monthly_cancellations()
    chart_weather()
    draw_er_diagram()
    print("Saved:")
    for path in sorted(IMAGES_DIR.glob("*.png")):
        print(f"  {path.name}")
