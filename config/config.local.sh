# Override signing identity — we don't have the developer's cert
export SIGNATURE_IDENTITY=""

# Qt 6.10.0 calls __yield() on ARM without including <arm_acle.h>.
# Apple clang 21+ treats this as -Werror. Downgrade to warning.
export QT_CXXFLAGS="-stdlib=libc++ -Wno-error=implicit-function-declaration"
