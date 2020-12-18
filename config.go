package main

import (
    "log"

    "github.com/BurntSushi/toml"
)

type tomlConfig struct {
    Database Database `toml:"Database"`
    AquametaUser AquametaUser `toml:"AquametaUser"`
    WebServer WebServer `toml:"WebServer"`
}

type Database struct {
    Role string
    Password string
    Host string
    Port uint32
    DatabaseName string
    EmbeddedPostgresRuntimePath string
}

type AquametaUser struct {
    Name string
    Email string
}

type WebServer struct {
    Protocol string
    IP string
    Port string
    SSLCertificateFile string
    SSLKeyFile string
}


func GetConfig() tomlConfig {
    var config tomlConfig
    if _, err := toml.DecodeFile("config.toml", &config); err != nil {
        log.Fatal(err)
    }

    return config
}
