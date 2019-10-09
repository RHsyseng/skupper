rs.initiate( {
   _id : "rs0",
   members: [
      { _id: 0, host: "mongo-svc-a.skuppman-db:27017" },
      { _id: 1, host: "mongo-svc-b.skuppman-db:27017" },
      { _id: 2, host: "mongo-svc-c.skuppman-db:27017" }
   ]
})
