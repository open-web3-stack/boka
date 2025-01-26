#!/usr/bin/env bash

set -e

swift build --package-path Boka

bin_path=$(swift build --package-path Boka --show-bin-path)/Boka

create_node() {
    local node_number=$1
    local port=$((9000 + node_number))
    local p2p_port=$((19000 + node_number))

    tmux send-keys -t boka "LOG_LEVEL=trace $bin_path --chain=minimal --rpc 127.0.0.1:$port --validator --dev-seed $node_number --p2p 127.0.0.1:$p2p_port --peers=127.0.0.1:19001 --peers=127.0.0.1:19002 --peers=127.0.0.1:19003 --name=node-$node_number" C-m

	sleep 1
}

# Start a new tmux session
tmux new-session -d -s boka

# Split the window into 3 panes
tmux split-window -v -t boka
tmux split-window -v -t boka

# Create nodes in each pane
for i in {1..3}
do
    tmux select-pane -t $((i-1))
    create_node $i
done

# Attach to the tmux session, -CC for iTerm2 integration
tmux -CC attach-session -t boka
