# Usage: ./create_string_to_secret.sh my-plaintext-unsafe-password
export PREPARED_PASSWORD=$(printf "$1" | shasum -a 256 | head -c 64 | openssl base64 -A)
printf "$PREPARED_PASSWORD" | python -c 'import bcrypt, sys; print(bcrypt.hashpw(sys.stdin.read().encode(), bcrypt.gensalt()).decode())'
