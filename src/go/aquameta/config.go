package main

import (
    "fmt"
    "log"

    "github.com/BurntSushi/toml"
)

type tomlConfig struct {
    DB database `toml:"database"`
    Webserver webserver `toml:"webserver"`
    Webrtc webrtc `toml:"webrtc"`
}

type database struct {
    Connection string
}

type webserver struct {
    IP string
    Port int
}

type webrtc struct {
    Stun string
}


func getConfig() tomlConfig {
    var config tomlConfig
    if _, err := toml.DecodeFile("config.toml", &config); err != nil {
        log.Fatal(err)
    }

    fmt.Printf("Database: %s", config.DB.Connection)
    fmt.Printf("Webserver: %s", config.Webserver.IP)

    return config

/*
    fmt.Printf("Title: %s\n", config.Title)
    fmt.Printf("Owner: %s (%s, %s), Born: %s\n",
        config.Owner.Name, config.Owner.Org, config.Owner.Bio,
        config.Owner.DOB)
    fmt.Printf("Database: %s %v (Max conn. %d), Enabled? %v\n",
        config.DB.Server, config.DB.Ports, config.DB.ConnMax,
        config.DB.Enabled)
    for serverName, server := range config.Servers {
        fmt.Printf("Server: %s (%s, %s)\n", serverName, server.IP, server.DC)
    }
    fmt.Printf("Client data: %v\n", config.Clients.Data)
    fmt.Printf("Client hosts: %v\n", config.Clients.Hosts)
*/
}
