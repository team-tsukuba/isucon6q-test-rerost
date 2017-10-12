
-- +goose Up
-- SQL in section 'Up' is executed when this migration is applied
ALTER TABLE entry ADD INDEX index_created_at(updated_at);


-- +goose Down
-- SQL section 'Down' is executed when this migration is rolled back
ALTER TABLE entry DROP INDEX index_created_at;
