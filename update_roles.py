import re
import sys

def update_roles(filename):
    with open(filename, 'r') as f:
        lines = f.readlines()

    new_lines = []
    i = 0
    while i < len(lines):
        line = lines[i]
        role_match = re.search(r'^(\s*)_Role: `([^`]+)`_(.*)', line)
        
        if role_match:
            indent = role_match.group(1)
            name = role_match.group(2)
            extra = role_match.group(3).strip()
            
            cleaned_extra = extra
            redundant_patterns = [
                re.compile(rf'^[ \t]*—\s*`enable_{name}`', re.IGNORECASE),
                re.compile(rf'^[ \t]*—\s*enable_{name}', re.IGNORECASE)
            ]
            
            for pattern in redundant_patterns:
                match = pattern.search(cleaned_extra)
                if match:
                    cleaned_extra = cleaned_extra[match.end():].strip()
                    break
            
            new_role_line = f"{indent}_Role: `{name}`_{' ' + cleaned_extra if cleaned_extra else ''}\n"
            new_lines.append(new_role_line)
            
            # Check if the next line is already the tag
            has_tag = False
            if i + 1 < len(lines):
                next_line = lines[i+1].strip()
                if next_line == f"_Ansible Tag: enable_{name}_":
                    has_tag = True
            
            if not has_tag:
                new_lines.append(f"{indent}_Ansible Tag: enable_{name}_\n")
        else:
            new_lines.append(line)
        
        i += 1

    with open(filename + '.new', 'w') as f:
        f.writelines(new_lines)

if __name__ == "__main__":
    update_roles(sys.argv[1])
