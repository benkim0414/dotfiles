nix --extra-experimental-features 'nix-command flakes' flake init -t nix-darwin/master
nix-shell -p git --run 'git clone https://github.com/benkim0414/dotfiles.git ~/workspace/dotfiles'
nix run nix-darwin --extra-experimental-features 'nix-command flakes' -- switch --flake ~/workspace/dotfiles/nix/darwin
