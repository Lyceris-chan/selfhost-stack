import os
import base64
import re

def parse_details(details_path):
    data = {}
    if not os.path.exists(details_path):
        return data
    
    with open(details_path, 'r') as f:
        lines = f.readlines()
    
    # Clean up lines: remove '│' and strip
    clean_lines = []
    for line in lines:
        line = line.replace('│', '').strip()
        if line:
            clean_lines.append(line)
    
    content = '\n'.join(clean_lines)
    
    # Extract username
    user_match = re.search(r'username\s+(\S+)', content)
    if user_match:
        data['REG_USER'] = user_match.group(1)
    
    # Extract docker token
    token_match = re.search(r'docker token\s+(\S+)', content)
    if token_match:
        data['REG_TOKEN'] = token_match.group(1)
    
    # Extract WireGuard config
    wg_start = content.find('[Interface]')
    if wg_start != -1:
        wg_conf = content[wg_start:].strip()
        data['WG_CONF_B64'] = base64.b64encode(wg_conf.encode()).decode()
    
    return data

def update_test_config(template_path, output_path, details_data):
    if not os.path.exists(template_path):
        print(f"Template {template_path} not found")
        return

    with open(template_path, 'r') as f:
        lines = f.readlines()
    
    new_lines = []
    for line in lines:
        if line.startswith('export LAN_IP='):
            new_lines.append('export LAN_IP="127.0.0.1"\n')
        elif line.startswith('export PUBLIC_IP='):
            new_lines.append('export PUBLIC_IP="127.0.0.1"\n')
        elif line.startswith('export ADMIN_PASS_RAW='):
            new_lines.append('export ADMIN_PASS_RAW="admin123"\n')
        elif line.startswith('export VPN_PASS_RAW='):
            new_lines.append('export VPN_PASS_RAW="vpn123"\n')
        elif line.startswith('export WG_CONF_B64='):
            val = details_data.get('WG_CONF_B64', '')
            new_lines.append(f'export WG_CONF_B64="{val}"\n')
        elif line.startswith('export REG_USER='):
             val = details_data.get('REG_USER', '')
             new_lines.append(f'export REG_USER="{val}"\n')
        elif line.startswith('export REG_TOKEN='):
             val = details_data.get('REG_TOKEN', '')
             new_lines.append(f'export REG_TOKEN="{val}"\n')
        elif '=' in line and not line.startswith('#'):
            # Populate other dummy values if empty
            key, val = line.split('=', 1)
            val = val.strip().strip('"').strip("'")
            if not val:
                new_lines.append(f'{key}="dummy"\n')
            else:
                new_lines.append(line)
        else:
            new_lines.append(line)
            
    # Add REG_USER/TOKEN if not in template but in details
    if 'REG_USER' not in [l.split('=')[0].replace('export ', '').strip() for l in new_lines if '=' in l]:
        new_lines.append(f'export REG_USER="{details_data.get("REG_USER", "")}"\n')
    if 'REG_TOKEN' not in [l.split('=')[0].replace('export ', '').strip() for l in new_lines if '=' in l]:
        new_lines.append(f'export REG_TOKEN="{details_data.get("REG_TOKEN", "")}"\n')

    with open(output_path, 'w') as f:
        f.writelines(new_lines)

if __name__ == "__main__":
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    details_path = os.path.join(repo_root, 'details')
    template_path = os.path.join(repo_root, 'test', 'test_config.template.env')
    output_path = os.path.join(repo_root, 'test', 'test_config.env')
    
    details_data = parse_details(details_path)
    update_test_config(template_path, output_path, details_data)
    print(f"Updated {output_path}")
