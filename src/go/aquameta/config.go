package main

import (
    "log"

    "github.com/BurntSushi/toml"
)

type tomlConfig struct {
    Database Database `toml:"Database"`
    User User `toml:"User"`
    Webserver Webserver `toml:"Webserver"`
    Webrtc Webrtc `toml:"Webrtc"`
}

type Database struct {
    User string
    Password string
    Host string
    Port uint32
    DatabaseName string
    RuntimePath string
}

type User struct {
    Name string
    Email string
}

type Webserver struct {
    Protocol string
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

    return config
}
