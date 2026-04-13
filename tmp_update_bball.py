import os

source_dir = 'e:/Projects/arbi_chief/lib/sports/streetball'
target_dir = 'e:/Projects/arbi_chief/lib/sports/basketball'

files = [
    ('streetball_scoring.dart', 'basketball_scoring.dart'),
    ('streetball_service.dart', 'basketball_service.dart'),
    ('streetball_providers.dart', 'basketball_providers.dart'),
    ('streetball_group_management_tab.dart', 'basketball_group_management_tab.dart'),
    ('streetball_cross_table_tab.dart', 'basketball_cross_table_tab.dart'),
]

for sf, tf in files:
    with open(os.path.join(source_dir, sf), 'r', encoding='utf-8') as f:
        content = f.read()
        
    # General replacements
    content = content.replace('Streetball', 'Basketball')
    content = content.replace('streetball', 'basketball')
    content = content.replace('Стрітбол', 'Баскетбол')
    
    # Specific replacements
    if 'scoring' in sf:
        # replace '21:0' with '20:0' - official Basketball forfeit score
        content = content.replace("'21:0'", "'20:0'")
        content = content.replace("'0:21'", "'0:20'")
    
    if 'service' in sf:
        # DB entity string generation
        content = content.replace('_sa_', '_ba_')
        content = content.replace('_sb_', '_bb_')
        
    with open(os.path.join(target_dir, tf), 'w', encoding='utf-8') as f:
        f.write(content)

print(f"Successfully processed {len(files)} files.")
