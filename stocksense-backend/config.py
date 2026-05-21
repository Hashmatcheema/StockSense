from dotenv import load_dotenv
import os

load_dotenv()

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GOOGLE_CUSTOM_SEARCH_API_KEY = os.getenv("GOOGLE_CUSTOM_SEARCH_API_KEY")
SEARCH_ENGINE_CX = os.getenv("SEARCH_ENGINE_CX")
SPREADSHEET_ID = os.getenv("SPREADSHEET_ID")
GMAIL_SENDER = os.getenv("GMAIL_SENDER")
PROJECT_ID = os.getenv("PROJECT_ID")
