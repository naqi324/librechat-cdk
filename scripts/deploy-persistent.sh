#!/bin/bash
# deploy-persistent.sh - Deploy with protection against CloudShell disconnection

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Persistent Deployment Setup${NC}"
echo "================================"
echo
echo "This script will help prevent CloudShell disconnection issues."
echo

# Check if already in screen/tmux
if [ -n "$STY" ]; then
    echo -e "${GREEN}✓ Already in screen session${NC}"
elif [ -n "$TMUX" ]; then
    echo -e "${GREEN}✓ Already in tmux session${NC}"
else
    echo -e "${YELLOW}⚠️  Not in a persistent session${NC}"
    echo
    echo "Choose protection method:"
    echo "1) screen (recommended)"
    echo "2) tmux"
    echo "3) nohup (background)"
    echo "4) Continue without protection"
    echo
    read -p "Enter choice (1-4) [1]: " choice
    choice=${choice:-1}
    
    case $choice in
        1)
            echo -e "\n${BLUE}Starting screen session...${NC}"
            echo "Remember: If disconnected, reconnect with: screen -r deploy"
            echo "Press Enter to continue..."
            read
            exec screen -S deploy "$0" "$@"
            ;;
        2)
            echo -e "\n${BLUE}Starting tmux session...${NC}"
            echo "Remember: If disconnected, reconnect with: tmux attach -t deploy"
            echo "Press Enter to continue..."
            read
            exec tmux new -s deploy "$0" "$@"
            ;;
        3)
            echo -e "\n${BLUE}Running in background with nohup...${NC}"
            LOG_FILE="deployment-$(date +%Y%m%d-%H%M%S).log"
            nohup npm run deploy:verbose > "$LOG_FILE" 2>&1 &
            PID=$!
            echo -e "${GREEN}Deployment started in background (PID: $PID)${NC}"
            echo "Monitor progress with: tail -f $LOG_FILE"
            echo "Check if running: ps -p $PID"
            exit 0
            ;;
        4)
            echo -e "${YELLOW}Continuing without protection...${NC}"
            ;;
    esac
fi

# Keep session active in background
(while true; do sleep 300; echo -n ""; done) &
KEEPALIVE_PID=$!
echo -e "${GREEN}✓ Keep-alive process started (PID: $KEEPALIVE_PID)${NC}"

# Trap to clean up keep-alive on exit
trap "kill $KEEPALIVE_PID 2>/dev/null || true" EXIT

# Show deployment info
echo -e "\n${BLUE}Deployment Information${NC}"
echo "====================="
echo "Start time: $(date)"
echo "Session type: ${STY:+screen}${TMUX:+tmux}${STY:-${TMUX:-unprotected}}"
echo

# Load environment
if [ -f .env ]; then
    source .env
    echo -e "${GREEN}✓ Environment loaded${NC}"
fi

# Run the deployment
echo -e "\n${BLUE}Starting deployment...${NC}"
echo "This will take 10-20 minutes. CloudShell will stay connected."
echo

# Use verbose deployment for better progress tracking
npm run deploy:verbose

echo -e "\n${GREEN}✅ Deployment completed successfully!${NC}"
echo "End time: $(date)"

# Clean up keep-alive
kill $KEEPALIVE_PID 2>/dev/null || true