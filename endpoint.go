package main

import (
    "context"
    "encoding/json"
    "fmt"
    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/lib/pq"
    "io"
    "io/ioutil"
    "log"
    "net/http"
    "net/url"
    "strings"
)

// endpoint API handler
func endpoint(dbpool *pgxpool.Pool) func(w http.ResponseWriter, req *http.Request) {
    apiHandler := func(w http.ResponseWriter, req *http.Request) {
        log.Println(req.Proto, req.Method, req.RequestURI)

        /*
        // CORS headers
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

        // Handle OPTIONS
        if req.Method == http.MethodOptions {
            w.WriteHeader(http.StatusNoContent)
            return apiHandler
        }
        */

        // path
        pathParts := strings.Split(req.URL.Path, "/")
        version := pathParts[2]
        path := strings.Join(pathParts[3:], "/")

        log.Println("Path parts: ", pathParts)

        if version != "0.5" {
            log.Print("💩💩💩💩💩💩 Reference to non-0.5 endpoint.")
        }

        // convert query string to JSON
        m, err := url.ParseQuery(req.URL.RawQuery)
        if err != nil {
            log.Fatal(err)
        }
        queryStringJSON, err := json.Marshal(m)
        if err != nil {
            log.Fatal(err)
        }

        // read request body
        r, err := ioutil.ReadAll(req.Body)
        if err != nil {
            log.Fatal(err)
        }
        requestBody := string(r)
        if requestBody == "" {
            requestBody = "{}"
        }

        // result strings
        var status int
        var message string
        var mimetype string
        var response string
        var response_headers string

        var dbQuery = fmt.Sprintf(
            "select * from endpoint.request(%v, %v, %v, %v::json, %v::json, %v::json)",
            pq.QuoteLiteral(version),
            pq.QuoteLiteral(req.Method),
            pq.QuoteLiteral(path),
            pq.QuoteLiteral(string(queryStringJSON)),
            pq.QuoteLiteral("{}"),
            pq.QuoteLiteral(requestBody),
        )


        log.Printf(dbQuery);

        // query endpoint.request()
        err = dbpool.QueryRow(context.Background(), dbQuery).Scan(&status, &message, &response, &mimetype, &response_headers)

        // unhandled exception in endpoint.request()
        if err != nil {
            log.Printf("💥💥💥💥 API Query failed, unhandled exception: %s", err)
            log.Printf("REQUEST:\nversion: %s\nmessage: %s\nresponse: %s\nmimetype: %s\n\n", version, message, response, mimetype)
            log.Printf("RESPONSE:\ndbQuery: %s\nreq.Proto: %s\nreq.RequestURI: %s\nrequestBody: %s\nqueryStringJSON: %s\n\n",
                 dbQuery, req.Proto, req.RequestURI, requestBody, queryStringJSON)
            return
        }

        // for(headers) Set(header)

        w.Header().Set("Content-Type", mimetype)
        w.WriteHeader(status)
        io.WriteString(w, response)
    }
    return apiHandler
}
