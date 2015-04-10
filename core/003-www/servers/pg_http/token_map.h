#pragma once
static const char *old_token_names[] = {
    /*[WSI_TOKEN_GET_URI]       =*/ "GET URI",
    /*[WSI_TOKEN_POST_URI]      =*/ "POST URI",
    /*[WSI_TOKEN_HOST]      =*/ "Host",
    /*[WSI_TOKEN_CONNECTION]    =*/ "Connection",
    /*[WSI_TOKEN_KEY1]      =*/ "key 1",
    /*[WSI_TOKEN_KEY2]      =*/ "key 2",
    /*[WSI_TOKEN_PROTOCOL]      =*/ "Protocol",
    /*[WSI_TOKEN_UPGRADE]       =*/ "Upgrade",
    /*[WSI_TOKEN_ORIGIN]        =*/ "Origin",
    /*[WSI_TOKEN_DRAFT]     =*/ "Draft",
    /*[WSI_TOKEN_CHALLENGE]     =*/ "Challenge",

    /* new for 04 */
    /*[WSI_TOKEN_KEY]       =*/ "Key",
    /*[WSI_TOKEN_VERSION]       =*/ "Version",
    /*[WSI_TOKEN_SWORIGIN]      =*/ "Sworigin",

    /* new for 05 */
    /*[WSI_TOKEN_EXTENSIONS]    =*/ "Extensions",

    /* client receives these */
    /*[WSI_TOKEN_ACCEPT]        =*/ "Accept",
    /*[WSI_TOKEN_NONCE]     =*/ "Nonce",
    /*[WSI_TOKEN_HTTP]      =*/ "Http",

    "Accept:",
    "If-Modified-Since:",
    "Accept-Encoding:",
    "Accept-Language:",
    "Pragma:",
    "Cache-Control:",
    "Authorization:",
    "Cookie:",
    "Content-Length:",
    "Content-Type:",
    "Date:",
    "Range:",
    "Referer:",
    "Uri-Args:",

    /*[WSI_TOKEN_MUXURL]    =*/ "MuxURL",
};

static const char *new_token_names[] = {
    "get ",
    "post ",
    "host:",
    "connection:",
    "sec-websocket-key1:",
    "sec-websocket-key2:",
    "sec-websocket-protocol:",
    "upgrade:",
    "origin:",
    "sec-websocket-draft:",
    "\x0d\x0a", // Apparently this is challenge?


    "key", // Don't have an analogue for this one.
    "version", // Don't have an analogue for this one.
    "sworigin", // Don't have an analogue for this one.


    "sec-websocket-extensions:",

    "sec-websocket-accept:",
    "sec-websocket-nonce:",
    "http/1.1 ",

    "accept:",
    "if-modified-since:",
    "accept-encoding:",
    "accept-language:",
    "pragma:",
    "cache-control:",
    "authorization:",
    "cookie:",
    "content-length:",
    "content-type:",
    "date:",
    "range:",
    "referer:",
    "uri-args:",

    "muxurl"

};
