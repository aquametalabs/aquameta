package main

import (
	"context"
	"fmt"
	socketio "github.com/googollee/go-socket.io"
	"github.com/jackc/pgx/v4"
	"github.com/jackc/pgx/v4/pgxpool"
	"io"
	"log"
	"net/http"
	"strings"
)

// ws handler
var sockets = make(map[string]socketio.Conn)
var listen = make(chan string)
var unlisten = make(chan string)

func websocket(dbpool *pgxpool.Pool) *socketio.Server {
	wsServer := socketio.NewServer(nil)

	wsServer.OnConnect("/", func(s socketio.Conn) error {
		log.Println("wsServer connected", s.ID())
		return nil
	})

	wsServer.OnEvent("/", "attach", func(s socketio.Conn, sessionId string) string {
		if sessionId == "null" {
			log.Println("wsServer attach received `null` as sessionId")
			return "err"
		}
		log.Println("wsServer attaching", sessionId)
		s.Emit("event", fmt.Sprintf("{\"type\": \"attached\", \"sessionId\": \"%s\"}", sessionId))
		sockets[sessionId] = s
		listen <- sessionId
		return "ok"
	})

	sendEvent := func(s socketio.Conn, event string) {
		s.Emit("event", fmt.Sprintf("{\"type\": \"event\", \"data\": %s}", string(event)))
	}

	go func(pool *pgxpool.Pool) {
		//  Need to acquire a connection that will LISTEN on this sessionId
		cn, err := pool.Acquire(context.Background())
		if err != nil {
			log.Println("wsServer could not acquire persistent connection: ", err)
			return
		}
		defer cn.Release()

		done := make(chan bool)
		var cancel func()

		start := func(cn *pgx.Conn) {
			done = make(chan bool)
			cancelctx, cncl := context.WithCancel(context.Background())
			cancel = cncl
			for {
				notification, er := cn.WaitForNotification(cancelctx)
				// WaitForNotification on a loop - blocking
				if er != nil {
					log.Println("wsServer notification error: ", er)
					break
				} else {
					log.Printf("wsServer notification %#v\n", notification.Channel)
					sessionId := notification.Channel
					sendEvent(sockets[sessionId], string(notification.Payload))
				}
			}
			close(done)
		}

		for {
			select {
			case sessionId := <-listen:
				if cancel != nil {
					cancel()
					cancel = nil
					// wait until done cancelling
					<-done
				}

				// listen
				_, err = cn.Exec(context.Background(), fmt.Sprintf("listen \"%s\"", sessionId))
				if err != nil {
					log.Println("wsServer error calling listen: ", err)
					return
				}

				// start wait process
				go start(cn.Conn())

				// select from event.event and publish those
				rows, err := pool.Query(context.Background(), "select event from event.event where session_id=$1;", sessionId)
				if err != nil {
					fmt.Println("wsServer error reading queued events:", err)
				}
				for rows.Next() {
					var event string
					err := rows.Scan(&event)
					if err != nil {
						fmt.Println("wsServer error scanning queued event:", err)
						continue
					}
					log.Printf("wsServer event.event: %#v\n", event)

					sendEvent(sockets[sessionId], event)
				}
				rows.Close()

			case sessionId := <-unlisten:
				if cancel != nil {
					cancel()
					cancel = nil
					// wait until done cancelling
					<-done
				}

				// unlisten
				_, err = cn.Exec(context.Background(), fmt.Sprintf("unlisten \"%s\"", sessionId))
				if err != nil {
					log.Println("wsServer error calling unlisten: ", err)
				}

				// start wait process
				go start(cn.Conn())

				_, err := pool.Exec(context.Background(), "delete from event.session where id=$1;", sessionId)
				if err != nil {
					fmt.Println("wsServer error deleting old session:", err)
				}
			}
		}
	}(dbpool)

	wsServer.OnError("/", func(_ socketio.Conn, e error) {
		// event.session_detach?
		log.Println("wsServer error:", e)
	})

	wsServer.OnDisconnect("/", func(_ socketio.Conn, reason string) {
		// event.session_detach?
		log.Println("wsServer closed", reason)
	})

	// serve websocket
	go func() {
		if err := wsServer.Serve(); err != nil {
			log.Fatalf("wsServer socketio listen error: %s\n", err)
		}
	}()

	return wsServer
}

func websocketDetach(w http.ResponseWriter, req *http.Request) {
	// /_socket/detach/${sessionId}
	s := strings.SplitN(req.URL.Path, "/", 4)
	sessionId := s[3]
	log.Println("wsServer detaching", sessionId)

	w.Header().Set("Content-Type", "text/plain")
	w.WriteHeader(200)
	io.WriteString(w, "")

	delete(sockets, sessionId)
	unlisten <- sessionId
}
