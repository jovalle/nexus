#!/usr/bin/env python3
"""
Update README.md with service listings from Docker Compose files.

This script extracts service information from all stack compose.yaml files
and updates the README.md with a formatted table of services organized by stack.
It looks for descriptions in:
1. homepage.description labels
2. Comments above service definitions (# description: ...)
3. Service name fallback
"""

import os
import re
import yaml
from pathlib import Path
from typing import Dict, List, Tuple, Optional

# Directories
SCRIPT_DIR = Path(__file__).parent
ROOT_DIR = SCRIPT_DIR.parent
STACKS_DIR = ROOT_DIR / "stacks"
README_PATH = ROOT_DIR / "README.md"
ROOT_COMPOSE = ROOT_DIR / "compose.yaml"


class ComposeParser:
    """Parse Docker Compose files and extract service information."""

    @staticmethod
    def extract_description(service_data: dict, service_name: str, compose_content: str) -> str:
        """
        Extract description from service data.

        Priority:
        1. homepage.description label
        2. Comment above service definition
        3. Empty string (no fallback)
        """
        # Try homepage.description label
        labels = service_data.get("labels", {})
        if isinstance(labels, dict):
            desc = labels.get("homepage.description")
            if desc:
                return desc
        elif isinstance(labels, list):
            for label in labels:
                if isinstance(label, str) and label.startswith("homepage.description:"):
                    return label.split(":", 1)[1].strip()

        # Try to find comment above service definition
        # Look for patterns like:
        # # Service description here
        # service_name:
        pattern = rf"#\s*(.+?)\n\s*{re.escape(service_name)}:"
        match = re.search(pattern, compose_content, re.MULTILINE)
        if match:
            comment = match.group(1).strip()
            # Clean up common comment prefixes
            comment = re.sub(r"^[-*]\s*", "", comment)
            if comment and not comment.startswith("!"):
                return comment

        # Return empty string if no description found
        return ""

    @staticmethod
    def extract_url(service_data: dict, domain: str = "DOMAIN") -> Optional[str]:
        """Extract URL from traefik labels if available."""
        labels = service_data.get("labels", {})

        if isinstance(labels, dict):
            for key, value in labels.items():
                if "traefik.http.routers" in key and ".rule" in key:
                    # Extract Host() from rule
                    match = re.search(r"Host\(`([^`]+)`\)", value)
                    if match:
                        host = match.group(1)
                        # Replace ${DOMAIN} or ${DOMAIN:?...} with placeholder
                        host = re.sub(r"\$\{DOMAIN[^}]*\}", domain, host)
                        return f"https://{host}"
        elif isinstance(labels, list):
            for label in labels:
                if isinstance(label, str) and "traefik.http.routers" in label and ".rule" in label:
                    match = re.search(r"Host\(`([^`]+)`\)", label)
                    if match:
                        host = match.group(1)
                        host = re.sub(r"\$\{DOMAIN[^}]*\}", domain, host)
                        return f"https://{host}"

        return None

    @staticmethod
    def parse_compose_file(compose_path: Path) -> List[Tuple[str, str, Optional[str]]]:
        """
        Parse a compose file and return list of (service_name, description, url).
        """
        if not compose_path.exists():
            return []

        try:
            # Read raw content for comment extraction
            with open(compose_path, "r") as f:
                compose_content = f.read()

            # Parse YAML
            with open(compose_path, "r") as f:
                data = yaml.safe_load(f)

            if not data or "services" not in data:
                return []

            services = []
            for service_name, service_data in data["services"].items():
                if not isinstance(service_data, dict):
                    continue

                # Skip commented out services (check in raw content)
                service_pattern = rf"^\s*#\s*{re.escape(service_name)}:"
                if re.search(service_pattern, compose_content, re.MULTILINE):
                    continue

                description = ComposeParser.extract_description(
                    service_data, service_name, compose_content
                )
                url = ComposeParser.extract_url(service_data)

                services.append((service_name, description, url))

            # Sort services alphabetically by name
            services.sort(key=lambda x: x[0].lower())
            return services

        except Exception as e:
            print(f"Error parsing {compose_path}: {e}")
            return []


class ReadmeUpdater:
    """Update README.md with service listings."""

    def __init__(self):
        self.stacks: Dict[str, List[Tuple[str, str, Optional[str]]]] = {}
        self.stack_headers: List[Tuple[str, str]] = []  # List of (display_name, stack_key)

    def parse_existing_stack_headers(self, content: str) -> List[Tuple[str, str]]:
        """
        Parse existing stack headers from README to determine order and which stacks to include.
        Returns list of (display_name, stack_key) tuples.
        Raises ValueError if the section doesn't exist.
        """
        headers = []

        # Find the Stack/Service Lineup section
        pattern = r"## 🏗️ Stack/Service Lineup.*?(?=\n## |\Z)"
        section_match = re.search(pattern, content, re.DOTALL)

        if not section_match:
            raise ValueError(
                "Error: '## 🏗️ Stack/Service Lineup' section not found in README.md\n"
                "Please add this section to define your stack structure."
            )

        section_content = section_match.group(0)

        # Find all h3 headers (### Stack Name)
        header_pattern = r"###\s+(.+?)$"
        for match in re.finditer(header_pattern, section_content, re.MULTILINE):
            display_name = match.group(1).strip()

            # Extract stack key from display name
            # Remove emoji and special chars, convert to lowercase
            stack_key = re.sub(r"[^\w\s-]", "", display_name).strip().lower()
            stack_key = re.sub(r"\s+", "-", stack_key)

            # Map common variations
            if "root" in stack_key:
                stack_key = "root"
            elif stack_key in ["app", "apps", "application", "applications"]:
                stack_key = "app"
            elif stack_key in ["core", "infrastructure", "infra"]:
                stack_key = "core"
            elif stack_key in ["data", "database", "storage"]:
                stack_key = "data"
            elif stack_key in ["log", "logs", "logging", "monitoring"]:
                stack_key = "log"
            elif stack_key in ["media", "movies", "tv", "entertainment"]:
                stack_key = "media"

            headers.append((display_name, stack_key))

        if not headers:
            raise ValueError(
                "Error: No stack headers (###) found in the '## 🏗️ Stack/Service Lineup' section\n"
                "Please add stack headers like '### � Root' to define your stacks."
            )

        return headers

    def collect_services(self):
        """Collect services from all stacks."""
        # Root compose
        if ROOT_COMPOSE.exists():
            services = ComposeParser.parse_compose_file(ROOT_COMPOSE)
            if services:
                self.stacks["root"] = services

        # Stack composes
        if STACKS_DIR.exists():
            for stack_dir in sorted(STACKS_DIR.iterdir()):
                if not stack_dir.is_dir():
                    continue

                compose_path = stack_dir / "compose.yaml"
                services = ComposeParser.parse_compose_file(compose_path)

                if services:
                    self.stacks[stack_dir.name] = services

    def validate_stacks(self) -> bool:
        """
        Validate that stacks in README match actual stack directories.
        Returns True if validation passes, False otherwise.
        """
        # Get stack keys from README headers
        readme_stacks = set(stack_key for _, stack_key in self.stack_headers)

        # Get actual stacks from filesystem
        actual_stacks = set(self.stacks.keys())

        # Check for mismatches
        missing_in_readme = actual_stacks - readme_stacks
        missing_in_filesystem = readme_stacks - actual_stacks

        if missing_in_readme or missing_in_filesystem:
            print("\n✗ Stack mismatch detected!")

            if missing_in_filesystem:
                print(f"\nStacks in README but missing compose files or services:")
                for stack in sorted(missing_in_filesystem):
                    expected_path = STACKS_DIR / stack / "compose.yaml" if stack != "root" else ROOT_COMPOSE
                    print(f"  - {stack} (expected at: {expected_path})")

            if missing_in_readme:
                print(f"\nStacks with services but missing in README:")
                for stack in sorted(missing_in_readme):
                    print(f"  - {stack}")
                    print(f"    Add a section like '### {stack.capitalize()}' to README.md")

            return False

        return True

    def generate_markdown_table(self, services: List[Tuple[str, str, Optional[str]]]) -> str:
        """Generate a paragraph format with stylish dividers for services."""
        lines = []

        for i, (service_name, description, url) in enumerate(services):
            # Format service name - check if it might already have manual markdown formatting
            # We'll use a simple bold format that users can enhance with links manually
            service_display = f"**{service_name.capitalize()}**"

            # Build the service entry
            if description:
                entry = f"{service_display} - {description}"
            else:
                entry = f"{service_display}"

            lines.append(entry)

        # Join with stylish dividers
        return " • ".join(lines)

    def generate_service_section(self) -> str:
        """Generate the complete service section for README."""
        lines = ["## 🏗️ Stack/Service Lineup", ""]
        lines.append(
            "This repository is structured for use with [Dockge](https://dockge.kuma.pet/), "
            "offering a clean UI to deploy and maintain Compose stacks:"
        )
        lines.append("")

        # Generate sections based on README headers (already parsed in update_readme)
        for display_name, stack_key in self.stack_headers:
            lines.append(f"### {display_name}")
            lines.append("")

            # Get services for this stack if they exist
            services = self.stacks.get(stack_key, [])

            if services:
                lines.append(self.generate_markdown_table(services))
            else:
                # No services found for this stack, leave empty or add placeholder
                lines.append("_No services defined_")

            lines.append("")

        return "\n".join(lines)

    def preserve_manual_enhancements(self, old_section: str, new_section: str) -> str:
        """
        Preserve manual URL enhancements in service names.
        Looks for [ServiceName](url) patterns in old content and preserves them in new content.
        """
        # Extract manual links from old section
        # Pattern: [ServiceName](url) or [Service Name](url)
        link_pattern = r"\[([^\]]+)\]\(([^\)]+)\)"
        manual_links = {}

        for match in re.finditer(link_pattern, old_section):
            link_text = match.group(1).strip()
            link_url = match.group(2).strip()
            # Store by lowercase for case-insensitive matching
            key = link_text.lower().replace(" ", "").replace("-", "").replace("_", "")
            manual_links[key] = (link_text, link_url)

        # Apply manual links to new section
        result = new_section
        for key, (link_text, link_url) in manual_links.items():
            # Try to find the service name in the new section
            # Look for **ServiceName** pattern (our generated format)
            patterns = [
                rf"\*\*{re.escape(link_text)}\*\*",  # Exact match
                rf"\*\*{re.escape(link_text.lower())}\*\*",  # Lowercase
                rf"\*\*{re.escape(link_text.capitalize())}\*\*",  # Capitalized
                rf"\*\*{re.escape(link_text.title())}\*\*",  # Title case
            ]

            for pattern in patterns:
                if re.search(pattern, result, re.IGNORECASE):
                    # Replace **ServiceName** with [ServiceName](url)
                    result = re.sub(
                        pattern, f"[**{link_text}**]({link_url})", result, flags=re.IGNORECASE
                    )
                    break

        return result

    def update_readme(self):
        """Update README.md with new service listings."""
        if not README_PATH.exists():
            print(f"Error: README.md not found at {README_PATH}")
            return False

        # Read current README
        with open(README_PATH, "r") as f:
            content = f.read()

        # Parse existing stack headers from README (may raise ValueError)
        try:
            self.stack_headers = self.parse_existing_stack_headers(content)
        except ValueError as e:
            print(f"\n{e}")
            return False

        # Validate that README stacks match actual stacks
        if not self.validate_stacks():
            return False

        # Generate new service section
        new_section = self.generate_service_section()

        # Find and extract old section for comparison
        pattern = r"## 🏗️ Stack/Service Lineup.*?(?=\n## |\Z)"
        old_match = re.search(pattern, content, re.DOTALL)

        if old_match:
            old_section = old_match.group(0)
            # Preserve manual enhancements (like URLs added by user)
            new_section = self.preserve_manual_enhancements(old_section, new_section)
            # Replace existing section
            updated_content = re.sub(pattern, new_section, content, flags=re.DOTALL)
        else:
            # This shouldn't happen since parse_existing_stack_headers would have raised
            print("Warning: Service lineup section not found, appending to end")
            updated_content = content.rstrip() + "\n\n" + new_section + "\n"

        # Write updated README
        with open(README_PATH, "w") as f:
            f.write(updated_content)

        print(f"✓ Updated README.md with {sum(len(s) for s in self.stacks.values())} services")
        print(f"  Stack headers from README: {', '.join(h[1] for h in self.stack_headers)}")
        print(f"  Stacks with services: {', '.join(sorted(self.stacks.keys()))}")
        return True


def main():
    """Main entry point."""
    print("Nexus README Updater")
    print("=" * 50)

    updater = ReadmeUpdater()

    print("Collecting services from compose files...")
    updater.collect_services()

    print(f"Found {len(updater.stacks)} stacks:")
    for stack_name, services in updater.stacks.items():
        print(f"  - {stack_name}: {len(services)} services")

    print("\nUpdating README.md...")
    success = updater.update_readme()

    if success:
        print("\n✓ README.md updated successfully!")
        return 0
    else:
        print("\n✗ Failed to update README.md")
        return 1


if __name__ == "__main__":
    exit(main())
