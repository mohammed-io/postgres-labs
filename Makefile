.PHONY: help install run clean

help:
	@echo "PostgreSQL Deep Dive Labs"
	@echo ""
	@echo "Targets:"
	@echo "  install    Install dependencies with uv"
	@echo "  run        Run Streamlit app"
	@echo "  clean      Clean generated files"

install:
	uv sync

run:
	uv run streamlit run main.py

clean:
	rm -rf .streamlit/__pycache__
	find . -type d -name __pycache__ -exec rm -rf {} +
