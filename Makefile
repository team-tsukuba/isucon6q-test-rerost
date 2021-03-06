system-reload:
	make nginx-reload
	make service-reload

service-reload:
	cd webapp/ruby
	(cd /home/isucon/webapp/ruby; ~/.local/ruby/bin/bundle install)
	sudo systemctl restart isuda.ruby.service
	cd

nginx-reload:
	sudo nginx -s reload

deploy:
	git pull
	make system-reload

db_up:
	/home/isucon/go/bin/goose up

db_down:
	/home/isucon/go/bin/goose down

db_status:
	/home/isucon/go/bin/goose status
