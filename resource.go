package main

import (
    "context"
    "fmt"
    "github.com/jackc/pgx/v4/pgxpool"
    "github.com/lib/pq"
    "io"
    "log"
    "net/http"
    "net/url"
)

func resource(dbpool *pgxpool.Pool) func(w http.ResponseWriter, req *http.Request) {
	/*
	 * resource handler
	 *
	 * 1. count the number of matching paths in
	 *   - endpoint.resource
	 *   - endpoint.resource_binary
	 *   - endpoint.template_route
	 * if count > 1, throw a 300 multiple choices
	 * if count < 1, throw 404 not found
	 *
	 * 2. grab the resource or template, serve the content
	 */
	resourceHandler := func(w http.ResponseWriter, req *http.Request) {
		log.Println(req.Proto, req.Method, req.RequestURI)

		// path
		// path := strings.SplitN(req.RequestURI,"?", 2)[0]
		path, err := url.QueryUnescape(req.URL.Path)
		if err != nil {
			log.Fatal(err)
		}

		// query string
		/*
		   m, err := url.ParseQuery(req.URL.RawQuery)
		   if err != nil { log.Fatal(err) }
		*/

		// count matching endpoint.resource
		// TODO: Learn to work with UUIDs in Go
		const matchCountQ = `
            select r.id::text, 'resource' as resource_table
            from endpoint.resource r
            where path = %v
            and active = true

            union

            select r.id::text, 'resource_binary'
            from endpoint.resource_binary r
            where path = %v
            and active = true`
		/*

		   -- union

		   -- select r.id::text, 'resource_function'
		   -- from endpoint.resource_function r
		   -- where regexp_match(%v, regexp_replace('^' || r.path_pattern || '$', '{\$\d+}', '(\S+)', 'g'))

		   union

		   select r.id::text, 'template'
		   from endpoint.template_route r
		   where %v ~ r.url_pattern`
		   // and active = true ?
		*/

		matches, err := dbpool.Query(context.Background(), fmt.Sprintf(
			matchCountQ,
			pq.QuoteLiteral(path),
			pq.QuoteLiteral(path)))
		if err != nil {
			log.Fatalf("Resource matching query failed: %v", err)
		}
		defer matches.Close()

		var id string
		var resourceTable string

		var n int32
		for matches.Next() {
			err = matches.Scan(&id, &resourceTable)
			if err != nil {
				return // FIXME
			}
			n++
		}

		// 300 Multiple Choices
		if n > 1 {
			http.Error(w, http.StatusText(http.StatusMultipleChoices), http.StatusMultipleChoices)
			return // FIXME?
		} else {
			// 404 Not Found
			if n < 1 {
				http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
				return // FIXME?
			}
		}

		var content string
		var contentBinary []byte
		var mimetype string

		switch resourceTable {
		case "resource":
			const resourceQ = `
                select r.content, m.mimetype
                from endpoint.resource r
                    join endpoint.mimetype m on r.mimetype_id = m.id
                where r.id = %v`

			err := dbpool.QueryRow(context.Background(), fmt.Sprintf(resourceQ, pq.QuoteLiteral(id))).Scan(&content, &mimetype)
			if err != nil {
				log.Printf("QueryRow failed: %v", err)
			}
			w.Header().Set("Content-Type", mimetype)
			w.WriteHeader(200)
			io.WriteString(w, content)

		// this is a mess
		/*
		   case "resource_function":
		       const resourceFunctionQ = `
		           select f.path_pattern, m.mimetype
		           from endpoint.resource_function r
		               join endpoint.mimetype m on r.mimetype_id = m.id
		               join %v.%v(%xxx)
		           where r.id = %v`

		       err := dbpool.QueryRow(context.Background(), fmt.Sprintf(resourceFunctionQ, pq.QuoteLiteral(id))).Scan(&content, &mimetype)
		       if err != nil {
		           log.Printf("QueryRow failed: %v", err)
		       }
		       w.Header().Set("Content-Type", mimetype)
		       w.WriteHeader(200)
		       w.Write(contentBinary)
		*/

		case "resource_binary":
			const resourceBinaryQ = `
                select r.content, m.mimetype
                from endpoint.resource_binary r
                    join endpoint.mimetype m on r.mimetype_id = m.id
                where r.id = %v`

			err := dbpool.QueryRow(context.Background(), fmt.Sprintf(resourceBinaryQ, pq.QuoteLiteral(id))).Scan(&contentBinary, &mimetype)
			if err != nil {
				log.Printf("QueryRow failed: %v", err)
			}
			w.Header().Set("Content-Type", mimetype)
			w.WriteHeader(200)
			w.Write(contentBinary)
		}

		/*
		       failed attempt at using pl/go solution
		   case "template":
		       const templateQ = `
		           select
		               endpoint.template_render(
		                   t.id::text, -- FIXME
		                   r.args::json::text, -- FIXME
		                   (array_to_json( regexp_matches(%v, r.url_pattern) ))::text -- FIXME
		               ) as content,
		               m.mimetype
		           from endpoint.template_route r
		               join endpoint.template t on r.template_id = t.id
		               join endpoint.mimetype m on t.mimetype_id = m.id`

		       err := dbpool.QueryRow(context.Background(), fmt.Sprintf(templateQ, pq.QuoteLiteral(path))).Scan(&content, &mimetype)
		       if err != nil {
		           log.Printf("QueryRow failed: %v", err)
		       }
		       w.Header().Set("Content-Type", mimetype)
		       w.WriteHeader(200)
		       io.WriteString(w, content)
		   case "resource_binary":
		       const resourceBinaryQ = `
		           select r.content, m.mimetype
		           from endpoint.resource_binary r
		               join endpoint.mimetype m on r.mimetype_id = m.id
		           where r.id = %v`

		       err := dbpool.QueryRow(context.Background(), fmt.Sprintf(resourceBinaryQ, pq.QuoteLiteral(id))).Scan(&contentBinary, &mimetype)
		       if err != nil {
		           log.Printf("QueryRow failed: %v", err)
		       }
		       w.Header().Set("Content-Type", mimetype)
		       w.WriteHeader(200)
		       w.Write(contentBinary)

		   }
		*/
	}
	return resourceHandler
}
