# Override signing identity — we don't have the developer's cert
export SIGNATURE_IDENTITY=""

# Use more cores (default is 4)
export DRAKETHREADS=12

# Qt version — MUST match the version in specs-updates.patch
# If you bump Qt, update both this and the patch
export QTVER=6.10.2
