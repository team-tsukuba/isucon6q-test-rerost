
-- +goose Up
-- SQL in section 'Up' is executed when this migration is applied
ALTER TABLE entry ADD INDEX keyword_index(keyword);
ALTER TABLE entry ADD INDEX keyword_length_index(keyword_length);
ALTER TABLE entry ADD INDEX keyword_length_to_keyword_index(keyword_length, keyword);
ALTER TABLE star ADD INDEX keyword_to_user_name_index(keyword, user_name);
ALTER TABLE star ADD index keyword_index_index(keyword);


-- +goose Down
-- SQL section 'Down' is executed when this migration is rolled back
ALTER TABLE entry DROP INDEX keyword_index;
ALTER TABLE entry DROP INDEX keyword_length_index;
ALTER TABLE entry DROP INDEX keyword_length_to_keyword_index;
ALTER TABLE star DROP INDEX keyword_to_user_name_index;
ALTER TABLE star DROP INDEX keyword_index_index;
