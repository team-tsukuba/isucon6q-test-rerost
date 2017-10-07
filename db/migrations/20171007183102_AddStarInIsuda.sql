
-- +goose Up
-- SQL in section 'Up' is executed when this migration is applied
CREATE TABLE star (
  keyword varchar(191) CHARSET utf8 NOT NULL,
  user_name varchar(191) CHARSET utf8 NOT NULL,
  created_at datetime
);


-- +goose Down
-- SQL section 'Down' is executed when this migration is rolled back
DROP TABLE star;
