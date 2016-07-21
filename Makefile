.PHONY: update auto

update:
	cd support && python difftags.py

auto:
	-test "master" = "$$(git rev-parse --abbrev-ref HEAD)" \
		&& python support/difftags.py \
		&& test " M data/tags" = "$$(git status --porcelain | grep 'data/tags')" \
		&& git add data doc \
		&& git commit -m "Auto-updated tags $$(date +'%Y-%m-%d')" \
		&& git push
	git checkout -- doc/
