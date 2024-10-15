#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <openssl/err.h>
#include <openssl/pkcs12.h>
#include <openssl/ssl3.h>

#include "helpers.h"

int generate_self_signed_cert_and_pkcs12(
    const unsigned char *private_key_buf,
    size_t private_key_len,
    const char *alt_name, // null terminated string
    unsigned char **pkcs12_data,
    int *pkcs12_len
) {
    X509 *cert = NULL;
    PKCS12 *p12 = NULL;
    EVP_PKEY *ed25519_key = NULL;
	unsigned char *temp_buf = NULL;
    int ret = 1;

    // Create EVP_PKEY from the provided Ed25519 private key buffer
    ed25519_key = EVP_PKEY_new_raw_private_key(EVP_PKEY_ED25519, NULL, private_key_buf, private_key_len);
    if (!ed25519_key) {
        goto cleanup;
    }

    // Create a new X509 certificate
    cert = X509_new();
    if (!cert) {
        goto cleanup;
    }

    // Set version to X509v3
    X509_set_version(cert, 2);

    // Set serial number (you might want to generate this randomly)
    ASN1_INTEGER_set(X509_get_serialNumber(cert), 1);

    // Set validity period (1 year)
    X509_gmtime_adj(X509_get_notBefore(cert), 0);
    X509_gmtime_adj(X509_get_notAfter(cert), 31536000L);

    // Set subject and issuer (self-signed, so they're the same)
    X509_NAME *name = X509_get_subject_name(cert);
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, (unsigned char *)"Self-Signed Cert", -1, -1, 0);
    X509_set_issuer_name(cert, name);

    // Set public key
    X509_set_pubkey(cert, ed25519_key);

    // Add Subject Alternative Name extension
    GENERAL_NAMES *alt_names = GENERAL_NAMES_new();
    GENERAL_NAME *gen_name = GENERAL_NAME_new();
    ASN1_IA5STRING *ia5 = ASN1_IA5STRING_new();
    ASN1_STRING_set(ia5, alt_name, -1);
    GENERAL_NAME_set0_value(gen_name, GEN_DNS, ia5);
    sk_GENERAL_NAME_push(alt_names, gen_name);
    X509_add1_ext_i2d(cert, NID_subject_alt_name, alt_names, 0, 0);
    GENERAL_NAMES_free(alt_names);

    // Self-sign the certificate
    if (!X509_sign(cert, ed25519_key, NULL)) {
        goto cleanup;
    }

	// Create PKCS12 structure
    p12 = PKCS12_create(NULL, "My Certificate", ed25519_key, cert, NULL, 0, 0, 0, 0, 0);
    if (!p12) {
        goto cleanup;
    }

    // Get the size of the DER-encoded PKCS12 structure
    *pkcs12_len = i2d_PKCS12(p12, NULL);
    if (*pkcs12_len <= 0) {
        goto cleanup;
    }

    // Allocate memory for the DER-encoded PKCS12 structure
    *pkcs12_data = malloc(*pkcs12_len);
    if (!*pkcs12_data) {
        goto cleanup;
    }

    // Reset the pointer to the start of the buffer
    temp_buf = *pkcs12_data;

    // Actually encode the PKCS12 structure
    *pkcs12_len = i2d_PKCS12(p12, &temp_buf);
    if (*pkcs12_len <= 0) {
		ret = 6;
        free(*pkcs12_data);
        *pkcs12_data = NULL;
        *pkcs12_len = 0;
        goto cleanup;
    }

    ret = 0;

cleanup:
	if (ret != 0) {
		ret = ERR_get_error();

	}
    X509_free(cert);
    PKCS12_free(p12);
    EVP_PKEY_free(ed25519_key);
    return ret;
}

char *get_error_string(int error) {
    return ERR_error_string(error, NULL);
}
