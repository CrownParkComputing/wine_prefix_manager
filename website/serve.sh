#!/bin/bash

# Simple local server for testing the website
echo "🚀 Starting Wine Prefix Manager Website locally..."
echo "📍 URL: http://localhost:8000"
echo "🛑 Press Ctrl+C to stop"
echo ""

# Check if Python 3 is available
if command -v python3 &> /dev/null; then
    python3 -m http.server 8000
elif command -v python &> /dev/null; then
    python -m http.server 8000
else
    echo "❌ Error: Python is required to serve the website locally"
    echo "Please install Python 3 or use a different web server"
    exit 1
fi 