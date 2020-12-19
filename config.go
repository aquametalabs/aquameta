package main

import (
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


func getConfig() (tomlConfig, error) {
    var config tomlConfig
    if _, err := toml.DecodeFile("boot.conf", &config); err != nil {
        return config, err
    }

    return config, nil
}
