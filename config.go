package main

import (
    "github.com/BurntSushi/toml"
)

type tomlConfig struct {
    Database Database `toml:"Database"`
    AquametaUser AquametaUser `toml:"AquametaUser"`
    HTTPServer HTTPServer `toml:"HTTPServer"`
}

type Database struct {
    Mode string
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

// TODO: This belongs in the database
type HTTPServer struct {
    Protocol string
    IP string
    Port string
    SSLCertificateFile string
    SSLKeyFile string
    StartupURL string
}


func getConfig(configFile string) (tomlConfig, error) {
    var config tomlConfig
    if _, err := toml.DecodeFile(configFile, &config); err != nil {
        return config, err
    }

    return config, nil
}
