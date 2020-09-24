package main

import (
    "fmt"
    "log"

    "github.com/BurntSushi/toml"
)

type tomlConfig struct {
    Database Database `toml:"Database"`
    Webserver Webserver `toml:"Webserver"`
    Webrtc Webrtc `toml:"Webrtc"`
}

type Database struct {
    Connection string
}

type Webserver struct {
    IP string
    Port string
    SSLCertificateFile string
    SSLKeyFile string
}

type Webrtc struct {
    Stun string
}


func GetConfig() tomlConfig {
    var config tomlConfig
    if _, err := toml.DecodeFile("config.toml", &config); err != nil {
        log.Fatal(err)
    }

    fmt.Printf("Database: %s\n", config.Database.Connection)
    fmt.Printf("Webserver: %s:%s\n", config.Webserver.IP, config.Webserver.Port)

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
