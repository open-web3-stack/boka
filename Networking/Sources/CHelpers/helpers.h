#include <stddef.h>

int generate_self_signed_cert_and_pkcs12(
    const unsigned char *private_key_buf,
    size_t private_key_len,
    const char *alt_name, // null terminated string
    unsigned char **pkcs12_data,
    int *pkcs12_len
);

char *get_error_string(int error);
