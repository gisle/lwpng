drop table server;
create table server (
   id             int auto_increment primary key,
   scheme         varchar(10) not null default "http",
   host           varchar(100) not null,
   port           int not null default 80,
   last_visit     int,
   status         char(1) not null default " ",
   robots_txt     int                   # fresh_until for the robots.txt file
);


drop table disallow;
create table disallow (
   server         int not null,
   path           varchar(255) not null
);


drop table uri;
create table uri (
   id             int auto_increment primary key,
   server         int not null,
   abs_path       varchar(255) not null default "/",
   last_visit     int,
   status_code    smallint,
   message        varchar(100),
   last_mod       int,
   etag           varchar(50),
   fresh_until    int,
   content_length int,
   entity         int,
   content_type   int
);


drop table entity;
create table entity (
  id    int auto_increment primary key,
  size  int not null,
  md5   char(32) not null
);


drop table links;
create table links (
  src   int not null,
  dest  int not null,
  type  char(1) not null
);


drop table media_types;
create table media_types (
  id    int auto_increment primary key,
  name  varchar(32) not null
);
