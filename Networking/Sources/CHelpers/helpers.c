#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/pkcs12.h>
#include <openssl/ssl3.h>
#include <openssl/x509v3.h>

#include "helpers.h"

// Function to parse certificate and extract public key and alternative name
int parse_pkcs12_certificate(const unsigned char *data, size_t length, unsigned char **public_key,
                             size_t *public_key_len, char **alt_name, char **error_message)
{
    int ret = -1;
    BIO *bio = NULL;
    PKCS12 *p12 = NULL;
    EVP_PKEY *pkey = NULL;
    X509 *cert = NULL;
    STACK_OF(X509) *ca = NULL;
    STACK_OF(GENERAL_NAME) *alt_names = NULL;

    bio = BIO_new_mem_buf(data, (int)length);
    if (!bio)
    {
        *error_message = strdup("Failed to create BIO.");
        goto cleanup;
    }
    p12 = d2i_PKCS12_bio(bio, NULL);
    if (!p12)
    {
        *error_message = strdup("Failed to parse PKCS12.");
        goto cleanup;
    }

    if (!PKCS12_parse(p12, NULL, &pkey, &cert, &ca))
    {
        *error_message = strdup("Failed to parse PKCS12 structure.");
        goto cleanup;
    }

    // Check if the key is ED25519
    int sig_alg = X509_get_signature_nid(cert);
    if (sig_alg != NID_ED25519)
    {
        *error_message = strdup("Certificate signature algorithm is not ED25519.");
        goto cleanup;
    }

    // Extract public key
    if (EVP_PKEY_get_raw_public_key(pkey, NULL, public_key_len) <= 0)
    {
        *error_message = strdup("Failed to get public key length.");
        goto cleanup;
    }
    *public_key = (unsigned char *)malloc(*public_key_len);
    if (!*public_key)
    {
        *error_message = strdup("Failed to allocate memory for public key.");
        goto cleanup;
    }

    if (EVP_PKEY_get_raw_public_key(pkey, *public_key, public_key_len) <= 0)
    {
        *error_message = strdup("Failed to extract public key.");
        goto cleanup;
    }

    // Extract alternative name
    alt_names = X509_get_ext_d2i(cert, NID_subject_alt_name, NULL, NULL);
    if (alt_names)
    {
        for (int i = 0; i < sk_GENERAL_NAME_num(alt_names); i++)
        {
            GENERAL_NAME *gen_name = sk_GENERAL_NAME_value(alt_names, i);
            if (gen_name->type == GEN_DNS)
            {
                ASN1_STRING *name = gen_name->d.dNSName;
                *alt_name = strdup((char *)ASN1_STRING_get0_data(name));
                break;
            }
        }
        sk_GENERAL_NAME_pop_free(alt_names, GENERAL_NAME_free);
    }

    if (!*alt_name)
    {
        *error_message = strdup("No alternative name found.");
        goto cleanup;
    }

    ret = EXIT_SUCCESS; // Success

cleanup:
    if (ret != 0 && *public_key)
    {
        free(*public_key);
        *public_key = NULL;
    }
    BIO_free(bio);
    PKCS12_free(p12);
    EVP_PKEY_free(pkey);
    X509_free(cert);
    sk_X509_pop_free(ca, X509_free);

    return ret;
}

int generate_self_signed_cert_and_pkcs12(const unsigned char *private_key_buf,
                                         size_t private_key_len,
                                         const char *alt_name, // null terminated string
                                         unsigned char **pkcs12_data, int *pkcs12_len)
{
    X509 *cert = NULL;
    PKCS12 *p12 = NULL;
    EVP_PKEY *ed25519_key = NULL;
    unsigned char *temp_buf = NULL;
    int ret = 1;
    // Create EVP_PKEY from the provided Ed25519 private key buffer
    ed25519_key =
        EVP_PKEY_new_raw_private_key(EVP_PKEY_ED25519, NULL, private_key_buf, private_key_len);
    if (!ed25519_key)
    {
        goto cleanup;
    }

    // Create a new X509 certificate
    cert = X509_new();
    if (!cert)
    {
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
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, (unsigned char *)"Self-Signed Cert", -1,
                               -1, 0);
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
    if (!X509_sign(cert, ed25519_key, NULL))
    {
        goto cleanup;
    }

    // Create PKCS12 structure
    p12 = PKCS12_create(NULL, "My Certificate", ed25519_key, cert, NULL, 0, 0, 0, 0, 0);
    if (!p12)
    {
        goto cleanup;
    }

    // Get the size of the DER-encoded PKCS12 structure
    *pkcs12_len = i2d_PKCS12(p12, NULL);
    if (*pkcs12_len <= 0)
    {
        goto cleanup;
    }

    // Allocate memory for the DER-encoded PKCS12 structure
    *pkcs12_data = malloc(*pkcs12_len);
    if (!*pkcs12_data)
    {
        goto cleanup;
    }

    // Reset the pointer to the start of the buffer
    temp_buf = *pkcs12_data;

    // Actually encode the PKCS12 structure
    *pkcs12_len = i2d_PKCS12(p12, &temp_buf);
    if (*pkcs12_len <= 0)
    {
        ret = 6;
        free(*pkcs12_data);
        *pkcs12_data = NULL;
        *pkcs12_len = 0;
        goto cleanup;
    }

    ret = 0;

cleanup:
    if (ret != 0)
    {
        ret = ERR_get_error();
    }
    X509_free(cert);
    PKCS12_free(p12);
    EVP_PKEY_free(ed25519_key);
    return ret;
}

char *get_error_string(int error) { return ERR_error_string(error, NULL); }
