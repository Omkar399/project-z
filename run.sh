#!/bin/bash

# ProjectZ Build & Run Script
# Usage: ./run.sh [-d|--debug]

# Parse arguments
DEBUG_MODE=false
for arg in "$@"; do
    if [[ "$arg" == "-d" ]] || [[ "$arg" == "--debug" ]]; then
        DEBUG_MODE=true
        break
    fi
done

# Kill existing processes
killall -9 ProjectZ 2>/dev/null
pkill -f "mem0_service/main.py" 2>/dev/null

# Start Mem0 Service
echo "🧠 Starting Mem0 service..."
cd mem0_service

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "⚠️  Python 3 not found. Mem0 service will not start."
    echo "   Install Python 3 to enable long-term memory features."
    cd ..
else
    # Check if dependencies are installed
    if [ ! -d "venv" ]; then
        echo "📦 Creating Python virtual environment..."
        python3 -m venv venv
        source venv/bin/activate
        echo "📦 Installing Mem0 dependencies..."
        pip install --quiet -r requirements.txt
    else
        source venv/bin/activate
    fi
    
    # Start Mem0 service in background
    echo "🚀 Starting Mem0 service on http://localhost:8420..."
    nohup python main.py > mem0_service.log 2>&1 &
    MEM0_PID=$!
    echo "   Mem0 PID: $MEM0_PID"
    
    # Wait a moment for service to start
    sleep 2
    
    # Check if service started successfully
    if curl -s http://localhost:8420/health > /dev/null 2>&1; then
        echo "✅ Mem0 service running"
    else
        echo "⚠️  Mem0 service may not have started correctly (check mem0_service/mem0_service.log)"
    fi
    
    cd ..
fi

echo "🔨 Building ProjectZ..."

# Build
xcodebuild -project Clippy.xcodeproj \
           -scheme ProjectZ \
           -destination 'platform=macOS,arch=arm64' \
           -configuration Debug \
           CODE_SIGN_IDENTITY="" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO \
           -quiet

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "✅ Build succeeded"

# Get app path
BUILD_SETTINGS=$(xcodebuild -project Clippy.xcodeproj -scheme ProjectZ -showBuildSettings -configuration Debug 2>/dev/null)
TARGET_BUILD_DIR=$(echo "$BUILD_SETTINGS" | grep " TARGET_BUILD_DIR =" | cut -d "=" -f 2 | xargs)
FULL_PRODUCT_NAME=$(echo "$BUILD_SETTINGS" | grep " FULL_PRODUCT_NAME =" | cut -d "=" -f 2 | xargs)
APP_PATH="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
EXECUTABLE_NAME=$(echo "$BUILD_SETTINGS" | grep " EXECUTABLE_NAME =" | cut -d "=" -f 2 | xargs)

if [ -d "$APP_PATH" ]; then
    if [ "$DEBUG_MODE" = true ]; then
        echo "🐛 Starting in Debug Mode..."
        echo "   Logs will appear below. Press Ctrl+C to stop."
        echo "   (Mem0 service will continue running in background)"
        echo ""
        "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
    else
        open "$APP_PATH"
        echo "🚀 App started: $APP_PATH"
        echo "📝 Note: Mem0 service running in background (http://localhost:8420)"
        echo "   To stop: pkill -f mem0_service/main.py"
    fi
else
    echo "❌ App not found at $APP_PATH"
    exit 1
fi
