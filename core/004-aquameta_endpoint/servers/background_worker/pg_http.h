PG_MODULE_MAGIC; // necessary for PostgreSQL modules

static int data_callback (struct libwebsocket_context *context,
                          struct libwebsocket *wsi,
                          enum libwebsocket_callback_reasons reason,
                          void *user,
                          void *in,
                          size_t len);
static int event_callback (struct libwebsocket_context *context,
                           struct libwebsocket *wsi,
                           enum libwebsocket_callback_reasons reason,
                           void *user,
                           void *in,
                           size_t len);
static void* handle_websocket (void *in);
static void pg_http_main (Datum main_arg);
void _PG_init (void);

// number of threads
static pthread_t thread[1000];

struct analyze_data_info {
    char *data;
    struct libwebsocket *wsi;
};
