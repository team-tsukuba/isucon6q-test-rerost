
-- +goose Up
-- SQL in section 'Up' is executed when this migration is applied
ALTER TABLE entry ADD keyword_length INTEGER;
ALTER TABLE entry ADD regrex_escape VARCHAR(300);
UPDATE entry SET keyword_length=character_length(keyword);

-- +goose Down
-- SQL section 'Down' is executed when this migration is rolled back
ALTER TABLE entry DROP COLUMN keyword_length;
ALTER TABLE entry DROP COLUMN regrex_escape;
