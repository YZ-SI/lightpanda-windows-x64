const std = @import("std");
const crypto = @import("../sys/libcrypto.zig");

const windows = std.os.windows;
const crypt32 = windows.crypt32;
const encoding: crypt32.ENCODING.TYPE = .{ .CERT = .ASN };
const disable_aia: crypt32.CERT_CHAIN = @bitCast(@as(u32, 0x00002000));
const server_auth_oids = [_]windows.LPCSTR{"1.3.6.1.5.5.7.3.1"};

const X509StoreContext = opaque {};
const X509Stack = opaque {};

extern "c" fn SSL_CTX_set_cert_verify_callback(
    ctx: *crypto.SSL_CTX,
    callback: *const fn (*X509StoreContext, ?*anyopaque) callconv(.c) c_int,
    arg: ?*anyopaque,
) void;
extern "c" fn X509_verify_cert(ctx: *X509StoreContext) c_int;
extern "c" fn X509_STORE_CTX_get_error(ctx: *const X509StoreContext) c_int;
extern "c" fn X509_STORE_CTX_set_error(ctx: *X509StoreContext, err: c_int) void;
extern "c" fn X509_STORE_CTX_get0_cert(ctx: *const X509StoreContext) ?*crypto.X509;
extern "c" fn X509_STORE_CTX_get0_untrusted(ctx: *const X509StoreContext) ?*X509Stack;
extern "c" fn i2d_X509(cert: *const crypto.X509, out: *?[*]u8) c_int;
extern "c" fn OPENSSL_sk_num(stack: *const X509Stack) usize;
extern "c" fn OPENSSL_sk_value(stack: *const X509Stack, index: usize) ?*crypto.X509;

const issuer_missing = 2; // X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT
const local_issuer_missing = 20; // X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY
const leaf_signature_unverifiable = 21; // X509_V_ERR_UNABLE_TO_VERIFY_LEAF_SIGNATURE
const verified = 0; // X509_V_OK

pub fn install(ctx: *crypto.SSL_CTX) void {
    SSL_CTX_set_cert_verify_callback(ctx, verify, null);
}

fn verify(ctx: *X509StoreContext, _: ?*anyopaque) callconv(.c) c_int {
    if (X509_verify_cert(ctx) == 1) return 1;
    switch (X509_STORE_CTX_get_error(ctx)) {
        issuer_missing, local_issuer_missing, leaf_signature_unverifiable => {},
        else => return 0,
    }

    // An early snapshot of ROOT can miss roots Windows retrieves on demand.
    // Send the supplied chain to the system chain engine as untrusted input.
    // libcurl still performs hostname and key-pin checks on the peer.
    if (!verifyWithSystemStore(ctx)) return 0;
    X509_STORE_CTX_set_error(ctx, verified);
    return 1;
}

fn verifyWithSystemStore(ctx: *X509StoreContext) bool {
    const leaf = X509_STORE_CTX_get0_cert(ctx) orelse return false;
    const store = crypt32.CertOpenStore(.MEMORY, .{}, .NULL, .{}, null) orelse return false;
    defer _ = crypt32.CertCloseStore(store, .{});

    var leaf_context: ?*const crypt32.CERT_CONTEXT = null;
    if (!addCertificate(store, leaf, &leaf_context)) return false;
    const cert = leaf_context orelse return false;
    defer _ = crypt32.CertFreeCertificateContext(cert);

    if (X509_STORE_CTX_get0_untrusted(ctx)) |stack| {
        for (0..OPENSSL_sk_num(stack)) |i| {
            const intermediate = OPENSSL_sk_value(stack, i) orelse return false;
            if (intermediate == leaf) continue;
            if (!addCertificate(store, intermediate, null)) return false;
        }
    }

    const chain_params: crypt32.CERT_CHAIN.PARA = .{
        .RequestedUsage = .{
            .dwType = .AND,
            .Usage = .{ .cUsageIdentifier = server_auth_oids.len, .rgpszUsageIdentifier = &server_auth_oids },
        },
    };
    var chain: *const crypt32.CERT_CHAIN.CONTEXT = undefined;
    // Do not retrieve intermediates from AIA URLs supplied by the peer. The
    // system can still refresh its own configured root trust cache.
    if (!crypt32.CertGetCertificateChain(.CURRENT_USER, cert, null, store, &chain_params, disable_aia, null, &chain).toBool()) return false;
    defer crypt32.CertFreeCertificateChain(chain);

    var https_policy: crypt32.HTTPSPolicyCallbackData = .{ .dwAuthType = .SERVER };
    const policy: crypt32.CERT_CHAIN.POLICY.PARA = .{ .dwFlags = .{}, .pvExtraPolicyPara = &https_policy };
    var status: crypt32.CERT_CHAIN.POLICY.STATUS = .{ .dwError = .SUCCESS, .lChainIndex = 0, .lElementIndex = 0, .pvExtraPolicyStatus = null };
    if (!crypt32.CertVerifyCertificateChainPolicy(.SSL, chain, &policy, &status).toBool()) return false;
    return status.dwError == .SUCCESS;
}

fn addCertificate(
    store: crypt32.HCERTSTORE,
    cert: *const crypto.X509,
    context: ?*?*const crypt32.CERT_CONTEXT,
) bool {
    var der: ?[*]u8 = null;
    const len = i2d_X509(cert, &der);
    const bytes = der orelse return false;
    defer crypto.OPENSSL_free(bytes);
    if (len <= 0) return false;
    return crypt32.CertAddEncodedCertificateToStore(store, encoding, bytes, @intCast(len), .USE_EXISTING, context).toBool();
}
