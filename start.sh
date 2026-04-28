#!/usr/bin/env bash
# HeartAI Startup Script
# Usage: ./start.sh

set -e

echo "🤍 HeartAI Startup"
echo "─────────────────────"

# Check API key
if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "⚠️  ANTHROPIC_API_KEY not set."
  echo "   Export it: export ANTHROPIC_API_KEY=sk-ant-..."
  echo ""
fi

# Check Python
if ! command -v python3 &>/dev/null; then
  echo "❌ Python 3 not found. Install it from python.org"
  exit 1
fi

# Install dependencies if needed
cd backend
if [ ! -d ".venv" ]; then
  echo "📦 Creating virtual environment..."
  python3 -m venv .venv
  source .venv/bin/activate
  pip install -q -r requirements.txt
  echo "✅ Dependencies installed"
else
  source .venv/bin/activate
fi

echo ""
echo "🚀 Starting HeartAI backend on http://localhost:8000"
echo "🌐 Open frontend/index.html in your browser"
echo "   (or: python3 -m http.server 3000 --directory ../frontend)"
echo ""
echo "Press Ctrl+C to stop."
echo ""

uvicorn main:app --host 0.0.0.0 --port 8000 --reload
