#pragma once
#include <openssl/bio.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/ec.h>
#include <openssl/ossl_typ.h>
#include <openssl/bn.h>
#include <openssl/crypto.h>
#include <openssl/opensslconf.h>
#include <openssl/obj_mac.h>
#include <openssl/err.h>
#include "log.h"
 
class SM2 {
private:
	/// <summary>
/// 通过公钥/私钥返回EVP_PKEY
/// </summary>
/// <param name="key">pem格式</param>
/// <param name="is_public"></param>
/// <param name="out_ecKey"></param>
/// <returns></returns>
	static bool CreateEVP_PKEY(unsigned char* key, int is_public, EVP_PKEY** out_ecKey);
public:	
	/// <summary>
	/// 根据私钥计算出公钥
	/// </summary>
	/// <param name="in_priKey"></param>
	/// <param name="out_pubKey"></param>
	/// <returns></returns>
	static bool PriKey2PubKey(string in_priKey, string& out_pubKey);
	/// <summary>
	/// 生成EC秘钥对 
	/// </summary>
	/// <param name="privKey">pem格式的私钥</param>
	/// <param name="pubKey">pem格式的公钥</param>
	/// <returns></returns>
	static int GenEcPairKey(string& out_priKey, string& out_pubKey);
 
	/// <summary>
	/// 签名 私钥加密 0成功
	/// </summary>
	/// <param name="in_buf">待签名数据</param>
	/// <param name="in_buflen">长度</param>
	/// <param name="out_sig">签名后数据</param>
	/// <param name="len_sig">签名数据长度</param>
	/// <param name="priKey">私钥pem格式</param>
	/// <returns></returns>
	static int Sign(string in_buf, int in_buflen, string& out_sig, int& len_sig, string priKey);
 
	/// <summary>
	/// 验签 公钥解密 0成功
	/// </summary>
	/// <param name="in_buf">待验签数据 明文</param>
	/// <param name="buflen">数据长度</param>
	/// <param name="sig">签名数据</param>
	/// <param name="siglen">签名数据长度</param>
	/// <param name="pubkey">公钥</param>
	/// <param name="keylen">公钥长度</param>
	/// <returns></returns>
	static int Verify(string in_buf, const int buflen, string sig, const int siglen, 
		string pubkey, const int keylen);
 
	/// <summary>
	/// 加密 公钥加密 0成功
	/// </summary>
	/// <param name="in_buf"></param>
	/// <param name="in_buflen"></param>
	/// <param name="out_encrypted"></param>
	/// <param name="len_encrypted"></param>
	/// <param name="pubKey">pem格式公钥</param>
	/// <returns></returns>
	static int Encrypt(string in_buf, int in_buflen, string& out_encrypted, int& len_encrypted, string pubKey);
 
	/// <summary>
	/// 解密 私钥解密 0成功
	/// </summary>
	/// <param name="in_buf"></param>
	/// <param name="in_buflen"></param>
	/// <param name="out_plaint"></param>
	/// <param name="len_plaint"></param>
	/// <param name="prikey">pem格式私钥</param>
	/// <returns></returns>
	static int Decrypt(string in_buf, int in_buflen, string& out_plaint, int& len_plaint, string prikey);
};
 
inline int SM2::GenEcPairKey(string& out_priKey, string& out_pubKey)
{
	EC_KEY* ecKey;
	EC_GROUP* ecGroup;
	int ret_val = -1;
	if (NULL == (ecKey = EC_KEY_new()))
	{
		return -1;
	}
 
	if (NULL == (ecGroup = EC_GROUP_new_by_curve_name(NID_X9_62_prime256v1)))
	{
		EC_KEY_free(ecKey);
		return -2;
	}
 
	if (EC_KEY_set_group(ecKey, ecGroup) != 1)
	{
		EC_GROUP_free(ecGroup);
		EC_KEY_free(ecKey);
		return -3;
	}
 
	if (!EC_KEY_generate_key(ecKey))
	{
		EC_GROUP_free(ecGroup);
		EC_KEY_free(ecKey);
		return -3;
	}
 
	//可以从EC_KEY类型返回char*数组
	size_t pri_len;
	size_t pub_len;
	char* pri_key = NULL;
	char* pub_key = NULL;
 
	BIO* pri = BIO_new(BIO_s_mem());
	BIO* pub = BIO_new(BIO_s_mem());
 
	PEM_write_bio_ECPrivateKey(pri, ecKey, NULL, NULL, 0, NULL, NULL);
	PEM_write_bio_EC_PUBKEY(pub, ecKey);
 
	pri_len = BIO_pending(pri);
	pub_len = BIO_pending(pub);
 
	pri_key = new char[pri_len + 1];
	pub_key = new char[pub_len + 1];
 
	BIO_read(pri, pri_key, pri_len);
	BIO_read(pub, pub_key, pub_len);
 
	pri_key[pri_len] = '\0';
	pub_key[pub_len] = '\0';
 
	out_pubKey = pub_key;
	out_priKey = pri_key;
 
	BIO_free_all(pub);
	BIO_free_all(pri);
	delete[] pri_key;
	delete[] pub_key;
	EC_GROUP_free(ecGroup);
	EC_KEY_free(ecKey);
	return 0;
}
 
inline bool SM2::CreateEVP_PKEY(unsigned char* key, int is_public, EVP_PKEY** out_pKey)
{
	BIO* keybio = NULL;
	keybio = BIO_new_mem_buf(key, -1);
 
	if (keybio == NULL) {
		LOGE("BIO_new_mem_buf failed.\n");
		return false;
	}
 
	if (is_public) {
		//*out_ecKey = PEM_read_bio_EC_PUBKEY(keybio, NULL, NULL, NULL);
		*out_pKey = PEM_read_bio_PUBKEY(keybio, NULL, NULL, NULL);
	}
	else {
		//*out_ecKey = PEM_read_bio_ECPrivateKey(keybio, NULL, NULL, NULL);
		*out_pKey = PEM_read_bio_PrivateKey(keybio, NULL, NULL, NULL);
	}
 
	if (*out_pKey == NULL) {
		LOGE("Failed to Get Key");
		BIO_free(keybio);
		return false;
	}
 
	BIO_free(keybio);
	return true;
}
 
inline bool SM2::PriKey2PubKey(string in_priKey, string& out_pubKey)
{
	BIO* keybio = NULL;
	keybio = BIO_new_mem_buf(in_priKey.c_str(), -1);
 
	if (keybio == NULL) {
		LOGE("BIO_new_mem_buf failed.\n");
		return false;
	}
 
	EC_KEY* ecKey = PEM_read_bio_ECPrivateKey(keybio, NULL, NULL, NULL);
	if (ecKey == NULL)
	{
		LOGE("PEM_read_bio_ECPrivateKey failed.");
		BIO_free(keybio);
		return false;
	}
 
	BIO* pub = BIO_new(BIO_s_mem());
	PEM_write_bio_EC_PUBKEY(pub, ecKey);
	int pub_len = BIO_pending(pub);
	char* pub_key = new char[pub_len + 1];
	BIO_read(pub, pub_key, pub_len);
	pub_key[pub_len] = '\0';
 
	out_pubKey = pub_key;
 
	delete[] pub_key;
	BIO_free(pub);
	BIO_free(keybio);
	return true;
}
 
inline int SM2::Sign(string in_buf, int in_buflen, string& out_sig, int& len_sig, string priKey)
{
	int ret_val = 0;
	//通过私钥得到EC_KEY
	EC_KEY* eckey = NULL;
	BIO* keybio = NULL;
	keybio = BIO_new_mem_buf(priKey.c_str(), -1);
	if (keybio == NULL)
	{
		LOGE("BIO_new_mem_buf failed\n");
		return -1;
	}
	eckey = PEM_read_bio_ECPrivateKey(keybio, NULL, NULL, NULL);
	if (eckey==NULL)
	{
		LOGE("PEM_read_bio_ECPrivateKey failed\n");
		BIO_free(keybio);
		return -2;
	}
 
	unsigned char szSign[256] = { 0 };
	if (1 != ECDSA_sign(0, (const unsigned char*)in_buf.c_str(), in_buflen, szSign, (unsigned int*)&len_sig, eckey)) {
		LOGE("ECDSA_sign failed\n");
		ret_val = -3;
	}
	else
	{
		out_sig = string((char*)szSign, len_sig);
		ret_val = 0;
	}
	BIO_free(keybio);
	EC_KEY_free(eckey);
	return ret_val;
}
 
inline int SM2::Verify(string in_buf, const int buflen, string sig, const int siglen,
	string pubkey, const int keylen)
{
	int ret_val = 0;
	//通过公钥得到EC_KEY
	EC_KEY* eckey = NULL;
	BIO* keybio = NULL;
	keybio = BIO_new_mem_buf(pubkey.c_str(), -1);
	if (keybio == NULL)
	{
		LOGE("BIO_new_mem_buf failed\n");
		return -1;
	}
	eckey = PEM_read_bio_EC_PUBKEY(keybio, NULL, NULL, NULL);
	if (eckey == NULL)
	{
		LOGE("PEM_read_bio_EC_PUBKEY failed\n");
		BIO_free(keybio);
		return -2;
	}
	if (1 != ECDSA_verify(0, (const unsigned char*)in_buf.c_str(), buflen, 
		(const unsigned char*)sig.c_str(), siglen, eckey))
	{
		LOGE("ECDSA_verify failed\n");
		ret_val = -3;
	}
	else
	{
		ret_val = 0;
	}
	BIO_free(keybio);
	EC_KEY_free(eckey);
 
	return ret_val;
}
 
 
inline int SM2::Encrypt(string in_buf, int in_buflen, string& out_encrypted, int& len_encrypted, string pubKey)
{
	int ret = -1, i;
	EVP_PKEY_CTX * ectx = NULL;
	EVP_PKEY* pkey = NULL;
	EC_KEY* key_pair = NULL;
	unsigned char* ciphertext = NULL;
	size_t ciphertext_len, plaintext_len;
 
	CreateEVP_PKEY((unsigned char*)pubKey.c_str(), 1, &pkey);
 
	/* compute SM2 encryption */
	if ((EVP_PKEY_set_alias_type(pkey, EVP_PKEY_SM2)) != 1)
	{
		LOGE("EVP_PKEY_set_alias_type failed.");
		goto clean_up;
	}
 
	if (!(ectx = EVP_PKEY_CTX_new(pkey, NULL)))
	{
		LOGE("EVP_PKEY_CTX_new failed.");
		goto clean_up;
	}
 
	if ((EVP_PKEY_encrypt_init(ectx)) != 1)
	{
		LOGE("EVP_PKEY_encrypt failed.");
		goto clean_up;
	}
 
	if ((EVP_PKEY_encrypt(ectx, NULL, &ciphertext_len, (const unsigned char*)in_buf.c_str(), in_buflen)) != 1)
	{
		LOGE("EVP_PKEY_set_alias_type failed.");
		goto clean_up;
	}
 
	if (!(ciphertext = (unsigned char*)malloc(ciphertext_len)))
	{
		goto clean_up;
	}
 
	if ((EVP_PKEY_encrypt(ectx, ciphertext, &ciphertext_len, (const unsigned char*)in_buf.c_str(), in_buflen)) != 1)
	{
		LOGE("EVP_PKEY_encrypt failed.");
		goto clean_up;
	}
	out_encrypted = string((char*)ciphertext, ciphertext_len);
	len_encrypted = ciphertext_len;
	ret = 0;
clean_up:
	if (pkey)
	{
		EVP_PKEY_free(pkey);
	}
 
	if (ectx)
	{
		EVP_PKEY_CTX_free(ectx);
	}
 
	if (ciphertext)
	{
		free(ciphertext);
	}
 
	return ret;
}
 
inline int SM2::Decrypt(string in_buf, int in_buflen, string& out_plaint, int& len_plaint, string prikey)
{
	int ret = -1, i;
	EVP_PKEY_CTX* pctx = NULL, * ectx = NULL;
	EVP_PKEY* pkey = NULL;
	EC_KEY* key_pair = NULL;
	unsigned char * plaintext = NULL;
	size_t ciphertext_len, plaintext_len;
 
	CreateEVP_PKEY((unsigned char*)prikey.c_str(), 0, &pkey);
 
	if ((EVP_PKEY_set_alias_type(pkey, EVP_PKEY_SM2)) != 1)
	{
		LOGE("EVP_PKEY_set_alias_type failed.");
		goto clean_up;
	}
 
	if (!(ectx = EVP_PKEY_CTX_new(pkey, NULL)))
	{
		LOGE("EVP_PKEY_CTX_new failed.");
		goto clean_up;
	}
 
	/* compute SM2 decryption */
	if ((EVP_PKEY_decrypt_init(ectx)) != 1)
	{
		LOGE("EVP_PKEY_decrypt_init failed.");
		goto clean_up;
	}
 
	if ((EVP_PKEY_decrypt(ectx, NULL, &plaintext_len, (const unsigned char*)in_buf.c_str(), in_buflen)) != 1)
	{
		LOGE("EVP_PKEY_decrypt failed.");
		goto clean_up;
	}
 
	if (!(plaintext = (unsigned char*)malloc(plaintext_len)))
	{
		goto clean_up;
	}
 
	if ((EVP_PKEY_decrypt(ectx, plaintext, &plaintext_len, (const unsigned char*)in_buf.c_str(), in_buflen)) != 1)
	{
		LOGE("EVP_PKEY_decrypt failed.");
		goto clean_up;
	}
	out_plaint = string((char*)plaintext, plaintext_len);
	len_plaint = plaintext_len;
	ret = 0;
clean_up:
	if (pctx)
	{
		EVP_PKEY_CTX_free(pctx);
	}
 
	if (pkey)
	{
		EVP_PKEY_free(pkey);
	}
 
	if (ectx)
	{
		EVP_PKEY_CTX_free(ectx);
	}
 
	if (plaintext)
	{
		free(plaintext);
	}
 
	return ret;
}

