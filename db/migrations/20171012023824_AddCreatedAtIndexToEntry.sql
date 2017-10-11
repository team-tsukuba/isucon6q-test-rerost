
-- +goose Up
-- SQL in section 'Up' is executed when this migration is applied
CREATE INDEX index_created_at ON entry;


-- +goose Down
-- SQL section 'Down' is executed when this migration is rolled back
DROP INDEX index_created_at;
