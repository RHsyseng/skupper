use pacman
db.createUser(
  {
    user: "blinky",
    pwd: "pinky",
    roles: [ { role: "readWrite", db: "pacman" } ]
  }
)

