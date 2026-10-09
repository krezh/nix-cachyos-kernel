set -euo pipefail

if [[ ! -f VERSION || ! -f flake.nix ]]; then
  echo "run update-sources from the repository root" >&2
  exit 1
fi

release=$(<VERSION)
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

kernel=$(nix-prefetch-github --json --rev "$release" CachyOS linux)
config=$(nix-prefetch-github --json CachyOS linux-cachyos)
patches=$(nix-prefetch-github --json CachyOS kernel-patches)

jq -nr \
  --argjson kernel "$kernel" \
  --argjson config "$config" \
  --argjson patches "$patches" \
  'def pin($source):
    "{\n    owner = \($source.owner | @json);\n    repo = \($source.repo | @json);\n    rev = \($source.rev | @json);\n    hash = \($source.hash | @json);\n  };";
  "{\n  kernel = \(pin($kernel))\n\n  config = \(pin($config))\n\n  patches = \(pin($patches))\n}\n"' > "$tmp"

install -m 0644 "$tmp" kernel-cachyos/sources.nix
