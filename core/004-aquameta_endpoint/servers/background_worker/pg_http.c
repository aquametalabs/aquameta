#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include <libwebsockets.h>

#include <postgres.h>
#include <postmaster/bgworker.h>
#include <executor/spi.h>
#include <storage/ipc.h>
#include <storage/latch.h>
#include <storage/proc.h>
#include <fmgr.h>
#include <utils/builtins.h>
#include <libpq-fe.h>

#include "pg_http.h"
#include "token_map.h"


static int current_thread = 0;

struct per_session_data__request {
    char *method;
    char *path;
    char *headers;
    char *request_body;
};

struct per_session_data__event {
    PGconn *conn;
};

static struct libwebsocket_protocols protocols[] = {
    { "http-only", data_callback, sizeof(struct per_session_data__request), 0 },
    { "echo", event_callback, 0 },
    { NULL, NULL, 0 }
};

/* Since we receive pieces of our request in bytes, we need a place to store
 * it in between callbacks. Heres as good as any.
 */
static size_t current_request_body_size = 0;
static char *current_request_body = NULL;

static void return_500(PGconn *conn, struct libwebsocket *wsi) {
    char buf[2048] = {0};
    size_t resp_header_len = sprintf(buf,
                              "HTTP/1.0 500 Internal Server Error\x0d\x0a"
                              "Server: pg_http\x0d\x0a"
                              "Content-Type: text/plain\x0d\x0a\x0d\x0a"
                              "%s", PQerrorMessage(conn));

    libwebsocket_write(wsi, (unsigned char*)buf, resp_header_len, LWS_WRITE_HTTP);
    libwebsocket_write(wsi, (unsigned char*)buf, resp_header_len, LWS_WRITE_HTTP);
    /* Close the socket because we assume it's bad that we're calling this function. */
    PQfinish(conn);
}


static int do_query (struct libwebsocket_context *context,
                     struct libwebsocket *wsi,
                     struct per_session_data__request *pss) {

    /* char *request_path; */
    char *response_status;
    char *response_message;
    char *response_data = NULL;
    char *response_mimetype;

    const char *query_params[4];
    unsigned char resp_header_buf[1024]; //TODO: create constant for headers buffer size
    unsigned char *resp_header = resp_header_buf;
    int resp_header_len;
    int pq_dirty = 0;
    int is_binary = 0;
    size_t binary_size = 0;

    PGconn *conn;
    PGresult *res = NULL;

    const size_t ps_path_siz = strlen(pss->path) + 1;
    char local_pss_path[ps_path_siz];
    memset(local_pss_path, '\0', ps_path_siz);
    memcpy(local_pss_path, pss->path, ps_path_siz);
    free(pss->path);

    elog(LOG, "%s %s %s", pss->method, local_pss_path, pss->request_body);

    conn = PQconnectdb("dbname=aquameta");

    if (PQstatus(conn) != CONNECTION_OK) {
        elog(LOG, "Connection to database failed: %s", PQerrorMessage(conn));
        return_500(conn, wsi);
        return -1;
    }

    res = PQexec(conn, "BEGIN");
    if (PQresultStatus(res) != PGRES_COMMAND_OK) {
        elog(LOG, "BEGIN command failed: %s", PQerrorMessage(conn));
        PQclear(res);
        return_500(conn, wsi);
        return -1;
    }
    PQclear(res);

    if (!strncmp("/endpoint", local_pss_path, 9)) {
        query_params[0] = pss->method; // strips base URL
        query_params[1] = local_pss_path + 9;
        query_params[2] = pss->headers;
        query_params[3] = pss->request_body;

        res = PQexecParams(conn,
                           pss->request_body ? "DECLARE curs CURSOR FOR select * from www.request($1, $2, $3, $4)"
                                             : "DECLARE curs CURSOR FOR select * from www.request($1, $2, $3, null)",
                           pss->request_body ? 4 : 3,
                           NULL,
                           query_params,
                           NULL,
                           NULL,
                           0); // binary?

        if (PQresultStatus(res) != PGRES_COMMAND_OK) {
            elog(LOG, "DECLARE CURSOR failed: %s", PQerrorMessage(conn));
            PQclear(res);
            return_500(conn, wsi);
            return -1;
        }
        PQclear(res);

        res = PQexec(conn, "FETCH ALL in curs");
        if (PQresultStatus(res) != PGRES_TUPLES_OK) {
            elog(LOG, "FETCH ALL failed: %s", PQerrorMessage(conn));
            PQclear(res);
            return_500(conn, wsi);
            return -1;
        }

        response_status = PQgetvalue(res, 0, 0);
        response_message = PQgetvalue(res, 0, 1);
        response_data = PQgetvalue(res, 0, 2);
        response_mimetype = "application/json";

        pq_dirty = 1;
    }
    /********************************************************************
     * TEXT RESOURCE
     *******************************************************************/
    else if (!strcmp(pss->method, "GET")) {
        query_params[0] = local_pss_path;

        res = PQexecParams(conn,
                           "DECLARE curs CURSOR FOR select content, m.mimetype from www.resource r join www.mimetype m on r.mimetype_id=m.id where r.path = $1",
                           1,
                           NULL,
                           query_params,
                           NULL,
                           NULL,
                           0); // binary?

        if (PQresultStatus(res) != PGRES_COMMAND_OK) {
            elog(LOG, "DECLARE CURSOR failed: %s", PQerrorMessage(conn));
            PQclear(res);
            return_500(conn, wsi);
            return -1;
        }
        PQclear(res);

        res = PQexec(conn, "FETCH ALL in curs");
        if (PQresultStatus(res) != PGRES_TUPLES_OK) {
            elog(LOG, "FETCH ALL failed: %s", PQerrorMessage(conn));
            PQclear(res);
            return_500(conn, wsi);
            return -1;
        }

        if (PQntuples(res)) {
            response_status = "200";
            response_message = "OK";
            response_data = PQgetvalue(res, 0, 0);
            response_mimetype = PQgetvalue(res, 0, 1);
        }
        /* if it's not a text resource, check for a binary image ELH */
        else {
            /********************************************************************
             * BINARY RESOURCE
             *******************************************************************/
            res = PQexec(conn, "CLOSE curs");
            PQclear(res);
            res = PQexecParams(conn,
                               "DECLARE curs BINARY CURSOR FOR select content, m.mimetype from www.resource_binary r join www.mimetype m on r.mimetype_id=m.id where r.path = $1",
                               1,
                               NULL,
                               query_params,
                               NULL,
                               NULL,
                               1); // binary?

            if (PQresultStatus(res) != PGRES_COMMAND_OK) {
                elog(LOG, "DECLARE CURSOR failed: %s", PQerrorMessage(conn));
                PQclear(res);
                return_500(conn, wsi);
                return -1;
            }
            PQclear(res);

            res = PQexec(conn, "FETCH ALL in curs");
            if (PQresultStatus(res) != PGRES_TUPLES_OK) {
                elog(LOG, "FETCH ALL failed: %s", PQerrorMessage(conn));
                PQclear(res);
                return_500(conn, wsi);
                return -1;
            }

            if (PQntuples(res)) {
                response_status = "200";
                response_message = "OK";
                response_data = PQgetvalue(res, 0, 0);
                binary_size = PQgetlength(res, 0, 0);
                response_mimetype = PQgetvalue(res, 0, 1);
                is_binary = 1;
            }
            else {
                response_status = "404";
                response_message = "Not Found";
                response_data = "<h1>Not Found</h1>";
                response_mimetype = "text/html";
            }

        }


        pq_dirty = 1;
    }
    else {
        // METHOD NOT ALLOWED
        elog(LOG, "Someone request an unimplemented method.");
        response_status = "405";
        response_message = "Not Allowed";
        response_mimetype = "text/html";
        response_data = "";
    }

    resp_header_len = sprintf((char*)resp_header,
                              "HTTP/1.0 %s %s\x0d\x0a"
                              "Server: pg_http\x0d\x0a"
                              "Content-Type: %s\x0d\x0a\x0d\x0a",
                              response_status,
                              response_message,
                              response_mimetype
                              );

    libwebsocket_write(wsi, resp_header_buf, resp_header_len, LWS_WRITE_HTTP);
    if (!is_binary) {
        libwebsocket_write(wsi, (unsigned char*)response_data, strlen(response_data), LWS_WRITE_HTTP);
    } else {
        libwebsocket_write(wsi, (unsigned char*)response_data, binary_size, LWS_WRITE_HTTP);
    }

    if (pq_dirty)
        PQclear(res);

    res = PQexec(conn, "CLOSE curs"); PQclear(res);
    res = PQexec(conn, "END"); PQclear(res);
    PQfinish(conn);

    return -1;
}


/* http://creativeandcritical.net/str-replace-c/ - public domain */
static char *replace_str(const char *str, const char *old, const char *new) {
    char *ret, *r;
    const char *p, *q;
    size_t oldlen = strlen(old);
    size_t count, retlen, newlen = strlen(new);

    if (oldlen != newlen) {
        for (count = 0, p = str; (q = strstr(p, old)) != NULL; p = q + oldlen)
            count++;
        /* this is undefined if p - str > PTRDIFF_MAX */
        retlen = p - str + strlen(p) + count * (newlen - oldlen);
    } else
        retlen = strlen(str);

    if ((ret = malloc(retlen + 1)) == NULL)
        return NULL;

    for (r = ret, p = str; (q = strstr(p, old)) != NULL; p = q + oldlen) {
        /* this is undefined if q - p > PTRDIFF_MAX */
        ptrdiff_t l = q - p;
        memcpy(r, p, l);
        r += l;
        memcpy(r, new, newlen);
        r += newlen;
    }
    strcpy(r, p);

    return ret;
}

static int data_callback (struct libwebsocket_context *context,
                          struct libwebsocket *wsi,
                          enum libwebsocket_callback_reasons reason,
                          void *user,
                          void *in,
                          size_t len) {

    struct per_session_data__request *pss = (struct per_session_data__request*) user;

    char buf[256];
    char *escaped_hdr;
    char hdr_hstore_part[256];
    char hdr_hstore[1024];

    switch (reason) {
        case LWS_CALLBACK_HTTP: // handle basic request
            pss->path = calloc(1, len + 1);
            memcpy(pss->path, in, len);

            if (len < 1) {
                libwebsockets_return_http_status(context, wsi, HTTP_STATUS_BAD_REQUEST, NULL);
                return -1;
            }

            if (lws_hdr_total_length(wsi, WSI_TOKEN_GET_URI)) {
                pss->method = "GET";
            }
            else if (lws_hdr_total_length(wsi, WSI_TOKEN_DELETE_URI)) {
                pss->method = "DELETE";
            }
            else if (lws_hdr_total_length(wsi, WSI_TOKEN_POST_URI)) {
                pss->method = "POST";
                return 0;
            }
            else if (lws_hdr_total_length(wsi, WSI_TOKEN_PATCH_URI)) {
                pss->method = "PATCH";
                return 0;
            }
            else if (lws_hdr_total_length(wsi, WSI_TOKEN_PUT_URI)) {
                pss->method = "PUT";
                return 0;
            }
            else {
                elog(LOG, "Unknown HTTP verb.");
                return -1;
            }

            strcpy(hdr_hstore, "");

            {
                int n = 0;
                const unsigned char *c;

                do {
                    c = lws_token_to_string(n);
                    if (!c) {
                        n++;
                        continue;
                    }

                    if (!lws_hdr_total_length(wsi, n)) {
                        n++;
                        continue;
                    }

                    int i;
                    const char *real_str = NULL;
                    for (i = 0; i < (sizeof(new_token_names)/sizeof(new_token_names[0])); i++) {
                        if (strcmp(new_token_names[i], (char *)c) == 0)
                            real_str = old_token_names[i];
                    }

                    if (!real_str) {
                        n++;
                        continue;
                    }

                    lws_hdr_copy(wsi, buf, sizeof buf, n);

                    escaped_hdr = replace_str(buf, "\"", "\\\"");

                    strcpy(hdr_hstore_part, "\"");
                    strcat(hdr_hstore_part, real_str);
                    strcat(hdr_hstore_part, "\"=>\"");
                    strcat(hdr_hstore_part, escaped_hdr);
                    strcat(hdr_hstore_part, "\"");

                    free(escaped_hdr);

                    if (n > 0) {
                        strcat(hdr_hstore, ",");
                    }

                    strcat(hdr_hstore, hdr_hstore_part);
                    n++;
                } while (c);
            }

            elog(LOG, "%s", hdr_hstore);

            pss->headers = hdr_hstore;

            return do_query(context, wsi, pss);

        case LWS_CALLBACK_HTTP_BODY: {// handle request body
            const size_t old_req_siz = current_request_body_size;
            if (current_request_body_size == 0) {
                /* New request? */
                current_request_body_size = len;
                current_request_body = calloc(1, len + 1);
            } else {
                /* Old request. Tack it on to the end of the existing buffer. */
                current_request_body_size += len;
                current_request_body = realloc(current_request_body, current_request_body_size + 1);
            }

            strncpy(current_request_body + old_req_siz, in, len);
            current_request_body[current_request_body_size] = '\0';

            break;
        }

        case LWS_CALLBACK_HTTP_BODY_COMPLETION: {
            pss->request_body = current_request_body;
            elog(LOG, "REQUEST BODY: %s", pss->request_body);

            do_query(context, wsi, pss);
            free(current_request_body);
            current_request_body_size = 0;

            return -1;
        }

        case LWS_CALLBACK_FILTER_NETWORK_CONNECTION:
            /* if we return non-zero from here, we kill the connection */
            break;

        case LWS_CALLBACK_GET_THREAD_ID:
            /*
             * if you will call "libwebsocket_callback_on_writable"
             * from a different thread, return the caller thread ID
             * here so lws can use this information to work out if it
             * should signal the poll() loop to exit and restart early
             */

            /* return pthread_getthreadid_np(); */
            break;

        default:
            break;
    }

    return 0;
}

static int event_callback (struct libwebsocket_context *context,
                           struct libwebsocket *wsi,
                           enum libwebsocket_callback_reasons reason,
                           void *user,
                           void *in,
                           size_t len) {

    struct per_session_data__event *pss = (struct per_session_data__event*) user;

    switch (reason) {
        case LWS_CALLBACK_ESTABLISHED:
            pss->conn = PQconnectdb("dbname=aquameta");
            elog(LOG, "pg_http: connection established");
            break;

        case LWS_CALLBACK_RECEIVE: {
            /* Braces here so we can do variable declaration. */
            struct analyze_data_info ainfo;
            ainfo.data = (char*) in;
            ainfo.wsi = wsi;

            pthread_create(&thread[++current_thread], NULL, handle_websocket, (void *)&ainfo);
            elog(LOG, "pg_http: received data: %s", (char *) in);
            break;
       }

        case LWS_CALLBACK_CLOSED:
            PQfinish(pss->conn);
            break;

        default:
            elog(LOG, "pg_http: receieved unkown callback.");
            break;
    }

    return 0;
}

static void* handle_websocket (void *in) {
    struct analyze_data_info *info = (struct analyze_data_info*) in;
    char *data = info->data;

    libwebsocket_write(info->wsi, (unsigned char*)data, strlen(data), LWS_WRITE_TEXT);

    return NULL;
}

static void pg_http_main (Datum main_arg) {
    struct lws_context_creation_info info = {0};
    struct libwebsocket_context *context;

    info.extensions = NULL;
    info.iface = NULL; // "lo0"; for mac, "lo" for linux
    info.options = 0;
    info.port = 8080;
    info.protocols = protocols;
    info.ssl_cert_filepath = NULL;
    info.ssl_private_key_filepath = NULL;

    context = libwebsocket_create_context(&info);

    if (context == NULL) {
        elog(LOG, "libwebsocket init failed\n");
    }
    else {
        BackgroundWorkerUnblockSignals();

        while (true) {
            libwebsocket_service(context, 50);
        }

        libwebsocket_context_destroy(context);
    }
}

void _PG_init (void) {
    BackgroundWorker worker;
    worker.bgw_flags = BGWORKER_SHMEM_ACCESS;
    worker.bgw_main = pg_http_main;
    worker.bgw_restart_time = 1;
    worker.bgw_notify_pid = 0;
    worker.bgw_start_time = BgWorkerStart_RecoveryFinished;
    snprintf(worker.bgw_name, BGW_MAXLEN, "pg_http");

    RegisterBackgroundWorker(&worker);
}
