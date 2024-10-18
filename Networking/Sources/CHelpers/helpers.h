#include <stddef.h>
#include <arpa/inet.h>

int parse_pkcs12_certificate(const unsigned char *data, size_t length,
                             unsigned char **public_key, size_t *public_key_len,
                             char **alt_name, char **error_message);

int generate_self_signed_cert_and_pkcs12(
    const unsigned char *private_key_buf,
    size_t private_key_len,
    const char *alt_name, // null terminated string
    unsigned char **pkcs12_data,
    int *pkcs12_len);

char *get_error_string(int error);

static inline uint16_t helper_ntohs(in_port_t netport)
{
    return ntohs(netport);
}
