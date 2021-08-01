# Function to set compatible ubuntu or debian version.
set_base_version() {
  [[ $ID = 'ubuntu' || $ID = 'debian' ]] && return;
  if [[ "$ID_LIKE" =~ ubuntu && -z $UBUNTU_CODENAME ]] || [[ "$ID_LIKE" =~ debian ]]; then
    ID_LIKE='debian'
    VERSION_CODENAME=$(apt-cache show tzdata | grep Provides | head -n 1 | cut -f2 -d '-')
  fi
}

# Helper function to update package lists.
update_lists_helper() {
  list=${1:-"$list_dir"/../sources.list}
  command -v sudo >/dev/null && SUDO=sudo
  ${SUDO} apt-get update -o Dir::Etc::sourcelist="$list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" 
}

# Function to update the package lists.
update_lists() {
  local ppa=${1:-}
  local ppa_url=${2:-}
  if [ ! -e /tmp/setup_php ] || [[ -n $ppa && -n $ppa_url ]]; then
    if [[ -n "$ppa" && -n "$ppa_url" ]]; then
      list="$list_dir"/"$(basename "$(grep -r "$ppa_url" "$list_dir" | cut -d ':' -f 1)")"
    fi
    update_lists_helper "$list"
    echo '' | sudo tee /tmp/setup_php 
  fi
}

# Function to add a gpg key
add_key() {
  ppa=${1:-ondrej/php}
  key_source=$2
  key_file=$3
  if [[ "$key_source" =~ launchpad.net|setup-php.com ]]; then
    fp=$(get -s -n '' "$lp_api"/~"${ppa%/*}"/+archive/"${ppa##*/}" | jq -r '.signing_key_fingerprint')
    key_source="$sks/pks/lookup?op=get&options=mr&exact=on&search=0x$fp"
  fi
  [ ! -e "$key_source" ] && get -q -n "$key_file" "$key_source"
  file_type=$(file "$key_file")
  if [[ "$file_type" =~ .*('Public-Key (old)'|'Secret-Key') ]]; then
    sudo gpg --batch --yes --dearmor "$key_file"  && sudo rm -f "$key_file"
    sudo mv "$key_file".gpg "$key_file"
  fi
}

# Helper function to add a PPA
add_list() {
  ppa=${1-ondrej/php}
  ppa_url=${2:-"$lp_ppa/$ppa/ubuntu"}
  key_source=${3:-"$ppa_url"}
  os_version=${4:-${UBUNTU_CODENAME:-$VERSION_CODENAME}}
  branch=${5:-main}
  arch=$(dpkg --print-architecture)
  [ -e "$key_source" ] && key_file=$key_source || key_file="$key_dir"/"${ppa/\//-}"-keyring.gpg
  grep -qr "$ppa_url" "$list_dir" && return;
  add_key "$ppa" "$key_source" "$key_file"
  echo "deb [arch=$arch signed-by=$key_file] $ppa_url $os_version $branch" | sudo tee "$list_dir"/"${ppa/\//-}".list 
  update_lists "$ppa" "$ppa_url"
}

# Function to remove a PPA
remove_list() {
  ppa=${1-ondrej/php}
  ppa_url=${2:-"$lp_ppa/$ppa/ubuntu"}
  grep -lr "$ppa_url" "$list_dir" | xargs -n1 sudo rm -f
  sudo rm -f "$key_dir"/"${ppa/\//-}"-keyring || true
}

# Function to add a PPA.
add_ppa() {
  ppa=${1:-ondrej/php}
  set_base_version
  if [ "$VERSION_ID" = "16.04" ] && [ "$ppa" = "ondrej/php" ]; then
    remove_list "$ppa"
    add_list "$ppa" https://setup-php.com/"$ppa"/ubuntu
  elif [[ "$ID" = "ubuntu" || "$ID_LIKE" =~ ubuntu ]] && [[ "$ppa" =~ "ondrej/" ]]; then
    add_list "$ppa"
  elif [[ "$ID" = "debian" || "$ID_LIKE" =~ debian ]] && [[ "$ppa" =~ "ondrej/" ]]; then
    add_list "$ppa" https://packages.sury.org/"${ppa##*/}"/ https://packages.sury.org/"${ppa##*/}"/apt.gpg
  else
    add_list "$ppa"
  fi
  . /etc/os-release
}

# Variables
list_dir='/etc/apt/sources.list.d'
lp_api='https://api.launchpad.net/1.0'
lp_ppa='http://ppa.launchpad.net'
key_dir='/usr/share/keyrings'
sks='https://keyserver.ubuntu.com'
