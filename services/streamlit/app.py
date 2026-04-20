import os
import streamlit as st
import streamlit.components.v1 as components

st.set_page_config(page_title="Suryan | Engineer Family", layout="wide")

# Umami Analytics (optional, enabled when env vars are provided).
UMAMI_HOST = os.getenv("UMAMI_HOST")
UMAMI_STREAMLIT_ID = os.getenv("UMAMI_STREAMLIT_ID")

if UMAMI_HOST and UMAMI_STREAMLIT_ID:
    components.html(
        f'<script async src="{UMAMI_HOST}/script.js" data-website-id="{UMAMI_STREAMLIT_ID}"></script>',
        height=0,
    )

st.title("Engineer Family Visualizations")
st.write("March Madness and more — coming soon.")
