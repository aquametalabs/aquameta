package main

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/jackc/pgx/v4/pgxpool"
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

		// api version, sub-path
		s := strings.SplitN(req.URL.Path, "/", 4)
		version, apiPath := s[2], s[3]

		if version != "0.3" {
			log.Print("💩💩💩💩💩💩 Referene to non-0.3 endpoint.")
		}

		// convert query string to JSON
		m, err := url.ParseQuery(req.URL.RawQuery)
		if err != nil {
			log.Fatal(err)
		}
		q, err := json.Marshal(m)
		if err != nil {
			log.Fatal(err)
		}
		queryStringJSON := string(q)
		if queryStringJSON == "" {
			queryStringJSON = "{}"
		}
		// qsJSON := strings.ReplaceAll(string(js), ",", ", ")

		/*
		   // convert req.Header JSON
		   headerJSON, err := json.Marshal(req.Header)
		   if err != nil { log.Fatal(err) }
		   log.Println(string(headerJSON))

		   // convert req.Header to bytes
		   headerBytes := bytes.Buffer{}
		   req.Header.Write(&headerBytes)
		*/

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

		var dbQuery = fmt.Sprintf(
			"select status, message, response, mimetype from endpoint.request(%v, %v, %v, %v::json, %v::json)",
			pq.QuoteLiteral(version),
			pq.QuoteLiteral(req.Method),
			pq.QuoteLiteral(apiPath),
			pq.QuoteLiteral(queryStringJSON),
			pq.QuoteLiteral(requestBody))

		// query endpoint.request()
		err = dbpool.QueryRow(context.Background(), dbQuery).Scan(&status, &message, &response, &mimetype)

		// unhandled exception in endpoint.request()
		if err != nil {
			log.Printf("💥💥💥💥 API Query failed, unhandled exception: %s", err)
			log.Printf("REQUEST:\nversion: %s\nmessage: %s\nresponse: %s\nmimetype: %s\n\n", version, message, response, mimetype)
			log.Printf("RESPONSE:\ndbQuery: %s\nreq.Proto: %s\nreq.RequestURI: %s\nrequestBody: %s\nqueryStringJSON: %s\n\n", dbQuery, req.Proto, req.RequestURI, requestBody, queryStringJSON)
			return
		}

		w.Header().Set("Content-Type", mimetype)
		w.WriteHeader(status)
		io.WriteString(w, response)
	}
	return apiHandler
}
