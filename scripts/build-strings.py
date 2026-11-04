"""Writes ios/Nook/Resources/Localizable.xcstrings (English source, Simplified Chinese).

Keys are the English strings used in SwiftUI (`Text("Upcoming")`, `Label(...)`, ...).
Interpolated keys use the format SwiftUI generates: `%lld` for integers, `%@` for strings.
The script also lists strings found in the Swift sources that have no entry here, so new
UI text does not silently stay English.

Usage: python -I scripts/build-strings.py <repo root>
"""

import json
import re
import sys
from pathlib import Path

# key -> Simplified Chinese
ZH = {
    "Today's agenda": "今日安排",
    "Today's upcoming events. System notifications follow each event's reminder setting.": "这里展示今天尚未结束的日程；系统通知按每条日程的提醒设置发送。",
    "No upcoming events today": "今天没有待办日程",
    "Add a timed event and choose a reminder to receive a notification.": "添加有具体时间的日程并选择提醒，即可接收通知。",
    "Undo": "撤销",
    "Redo": "重做",
    "Heading": "标题",
    "Body": "正文",
    "Bold": "粗体",
    "Italic": "斜体",
    "Text Format": "格式",
    "Hide Keyboard": "收起键盘",
    "Unlock once with your master password to enable quick unlock on this device.": "请先用主密码解锁一次，以在这台设备上启用快捷解锁。",
    "Quick unlock unavailable (Keychain %lld). Use your master password.": "快捷解锁不可用（钥匙串 %lld），请使用主密码。",
    "Device authentication failed. Use your master password or try again.": "系统身份认证失败，请重试或使用主密码。",
    "All-day events don't send reminders. Choose a start time to receive a notification.": "全天日程暂不发送提醒。请选择具体时间以接收通知。",
    "Reminds you before the start, using a local notification. Allow notifications in iOS Settings. Past reminder times are skipped.": "按所选提前量发送本机通知，需在 iOS 设置中允许通知；已过去的提醒时间会跳过。",
    "A trip groups related events. To receive reminders, add timed events to it and set their reminder times.": "行程用于归组相关日程；如需提醒，请添加有具体时间的日程并设置提前量。",
    "Anniversaries show a countdown; they don't send notifications yet.": "纪念日目前用于展示倒计时，暂不发送通知。",
    "Vault storage unavailable": "密码库暂时无法读取",
    "Unlock the vault before changing its master password.": "修改主密码前请先解锁密码库。",
    "Restart Nook to try again. Your saved vault has not been changed.": "请重新启动 Nook 后再试，已保存的密码库没有被修改。",
    "%lld accounts · %lld categories": "%lld 个账号 · %lld 个分类",
    "%@ left this month": "本月还剩 %@",
    "%@ of %@": "已用 %1$@ / 预算 %2$@",
    "%lld open": "%lld 项未完成",
    "+%lld more": "还有 %lld 项",
    "About": "关于",
    "Account": "账号",
    "Accounts": "账号",
    "Add": "添加",
    "Add Account": "添加账号",
    "Add Event": "添加日程",
    "Add Expense": "记一笔支出",
    "Add Income": "记一笔收入",
    "Add item": "添加事项",
    "Add notes": "添加备注",
    "All": "全部",
    "All Items": "全部项目",
    "All day": "全天",
    "Amount": "金额",
    "Anniversaries": "纪念日",
    "Anniversary": "纪念日",
    "Appearance": "外观",
    "Back to this week": "回到本周",
    "Birthday": "生日",
    "Budget %@": "预算 %@",
    "Calendar": "日历",
    "Cancel": "取消",
    "Cards": "卡片",
    "Category": "分类",
    "Checklist": "清单",
    "Choose a Day": "选择日期",
    "Choose a day": "选择日期",
    "Clear": "清除",
    "Content": "内容",
    "Copy": "复制",
    "Custom": "自定义",
    "Daily average %@": "日均 %@",
    "Daily spending chart": "每日支出图表",
    "Dark": "深色",
    "Data": "数据",
    "Date": "日期",
    "Day": "日期",
    "Day %lld of %lld": "第 %1$lld 天 / 共 %2$lld 天",
    "Delete": "删除",
    "Delete Event": "删除日程",
    "Delete Note": "删除便签",
    "Delete this event?": "删除这个日程？",
    "Delete this note?": "删除这条便签？",
    "Description (optional)": "说明（可选）",
    "Details": "详情",
    "Done": "完成",
    "Edit Event": "编辑日程",
    "Edited %@": "%@编辑",
    "Ends": "结束",
    "Enter an amount like 12.50": "请输入金额，例如 12.50",
    "Entertainment": "娱乐",
    "Event": "日程",
    "Expense": "支出",
    "Expense added": "已记录支出",
    "Expenses (This Month)": "本月支出",
    "Expenses (This Week)": "本周支出",
    "Export Backup": "导出备份",
    "Finance": "记账",
    "Finished": "已结束",
    "Food": "餐饮",
    "Food & Dining": "餐饮",
    "Fun": "娱乐",
    "Good Afternoon": "下午好",
    "Good Evening": "晚上好",
    "Good Morning": "早上好",
    "Health": "健康",
    "Home": "首页",
    "Housing": "居住",
    "Income": "收入",
    "Income added": "已记录收入",
    "Life": "生活",
    "Light": "浅色",
    "Location": "地点",
    "Mark as done": "标记为完成",
    "Mark as not done": "标记为未完成",
    "Marks the item as done": "将此事项标记为完成",
    "Monthly Budget": "每月预算",
    "More": "更多",
    "More filters": "更多筛选",
    "My Vault": "我的密码库",
    "New Event": "新建日程",
    "New Note": "新建便签",
    "Next week": "下一周",
    "No anniversaries yet": "还没有纪念日",
    "No events": "没有日程",
    "No matching items": "没有匹配的项目",
    "No matching notes": "没有匹配的便签",
    "No notes yet": "还没有便签",
    "No notifications": "没有通知",
    "No spending yet": "暂无支出",
    "No transactions yet": "还没有账目",
    "No trips yet": "还没有行程",
    "Note": "便签",
    "Note not found": "找不到这条便签",
    "Notes": "便签",
    "Nothing planned. Enjoy the free time.": "没有安排，享受空闲时光吧。",
    "Notifications": "通知",
    "Open Trip Plan": "打开行程计划",
    "Other": "其他",
    "Others": "其他",
    "Over budget by %@": "超出预算 %@",
    "Password": "密码",
    "Password hidden": "密码已隐藏",
    "Personal": "个人",
    "Pin": "置顶",
    "Pinned": "已置顶",
    "Preparing backup…": "正在准备备份…",
    "Previous week": "上一周",
    "Profile and settings": "个人资料与设置",
    "Project": "项目",
    "Quick Add": "快速添加",
    "Recent Note": "最近便签",
    "Recent Transactions": "最近账目",
    "Recently edited": "最近编辑",
    "Reminders for today's events will show up here.": "今天日程的提醒会显示在这里。",
    "Remove item": "删除事项",
    "Salary": "工资",
    "Save": "保存",
    "Schedule": "日程",
    "Search accounts or passwords": "搜索账号或密码",
    "Search notes": "搜索便签",
    "Secure Vault": "安全密码库",
    "Settings": "设置",
    "Shopping": "购物",
    "Sort by": "排序方式",
    "Sort notes": "便签排序",
    "Spending by Category": "支出分类",
    "Starts": "开始",
    "Starts at %@": "%@ 开始",
    "Storage": "存储",
    "System": "跟随系统",
    "Tap + to add an expense.": "点 + 记一笔支出。",
    "Tap + to plan something.": "点 + 添加日程。",
    "Tap + to write your first note.": "点 + 写下第一条便签。",
    "Theme": "主题",
    "This Month": "本月",
    "This Week": "本周",
    "Title": "标题",
    "To-do": "待办事项",
    "To-dos": "待办",
    "Today": "今天",
    "Total": "合计",
    "Transactions": "账目",
    "Transfer": "转账",
    "Transport": "交通",
    "Travel": "旅行",
    "Trips": "行程",
    "Try another word or category.": "换个关键词或分类试试。",
    "Turns %lld": "%lld 岁",
    "Unpin": "取消置顶",
    "Untitled": "无标题",
    "Upcoming": "即将开始",
    "Username": "用户名",
    "Vault": "密码库",
    "Version": "版本",
    "View All": "查看全部",
    "Work": "工作",
    "Write something…": "写点什么…",
    "Your accounts and passwords are encrypted and safe.": "你的账号和密码经过加密，安全可靠。",
    "day left": "天后",
    "day since": "天前",
    "days left": "天后",
    "days since": "天前",
    "At least 8 characters. Nook can't recover a forgotten master password: without it the vault can only be reset.": "至少 8 个字符。主密码忘记后无法找回，只能重置密码库。",
    "Couldn't add the photo": "无法添加照片",
    "Couldn't create the vault. Please try again.": "创建密码库失败，请重试。",
    "Couldn't restore the backup": "恢复备份失败",
    "Couldn't save the change": "更改未能保存",
    "Storage unavailable: changes won't be kept": "存储不可用：更改不会被保存",
    "The two passwords don't match.": "两次输入的密码不一致。",
    "This deletes every saved account and the master password. It can't be undone.": "这会删除所有已保存的账号和主密码，且无法撤销。",
    "What's the plan?": "有什么安排？",
    "Without the master password the saved items can't be decrypted. Resetting deletes them and lets you choose a new master password.": "没有主密码就无法解密已保存的内容。重置会删除这些内容，之后可以设置新的主密码。",
    "%@ copied for 90 seconds": "已复制%@，90 秒后自动清除",
    "%lld minutes before": "提前 %lld 分钟",
    "1 day before": "提前 1 天",
    "1 hour before": "提前 1 小时",
    "2 hours before": "提前 2 小时",
    "A backup is a JSON file with your notes, schedule and finance records. Photos and the vault are not included.": "备份是一个 JSON 文件，包含便签、日程和记账数据，不含照片和密码库。",
    "Add Field": "添加字段",
    "Add Photo": "添加照片",
    "At least 8 characters.": "至少 8 个字符。",
    "At start time": "开始时",
    "Backup restored": "备份已恢复",
    "Birthdays and special days, with a countdown.": "生日和重要的日子，带倒计时。",
    "Card": "卡片",
    "Card Number": "卡号",
    "Cardholder": "持卡人",
    "Change Master Password": "修改主密码",
    "Change Password": "修改密码",
    "Copied": "已复制",
    "Copy password": "复制密码",
    "Create Plan Note": "创建计划便签",
    "Create Vault": "创建密码库",
    "Create a master password": "设置主密码",
    "Create the vault in the Vault tab first.": "请先在密码库页面创建密码库。",
    "Currency": "货币",
    "Current master password": "当前主密码",
    "Delete All Vault Items": "删除密码库全部内容",
    "Delete Anniversary": "删除纪念日",
    "Delete Item": "删除项目",
    "Delete Trip": "删除行程",
    "Delete this anniversary?": "删除这个纪念日？",
    "Delete this item?": "删除这个项目？",
    "Delete this record?": "删除这条记录？",
    "Delete this trip?": "删除这个行程？",
    "Destination": "目的地",
    "Detail": "信息",
    "Edit": "编辑",
    "Edit Anniversary": "编辑纪念日",
    "Edit Expense": "编辑支出",
    "Edit Income": "编辑收入",
    "Edit Item": "编辑项目",
    "Edit Trip": "编辑行程",
    "Edit trip": "编辑行程",
    "Everything stays on this iPhone": "所有数据都保存在这台 iPhone 上",
    "Expiry": "有效期",
    "Face ID": "面容 ID",
    "Favorite": "收藏",
    "Fields": "字段",
    "Forgot master password?": "忘记主密码？",
    "Generate password": "生成密码",
    "Hide": "隐藏",
    "Hide password": "隐藏密码",
    "It encrypts everything you keep in the vault.": "密码库里的所有内容都用它加密。",
    "Its events and plan note are kept.": "相关日程和计划便签会保留。",
    "Keep passwords & accounts secure": "安全保存账号和密码",
    "Label": "名称",
    "Lock Vault": "锁定密码库",
    "Master Password": "主密码",
    "Master password": "主密码",
    "Master password changed": "主密码已修改",
    "Money": "记账",
    "Name": "名称",
    "New Anniversary": "新建纪念日",
    "New Item": "新建项目",
    "New Trip": "新建行程",
    "New master password": "新主密码",
    "No accounts yet": "还没有账号",
    "None": "无",
    "Notes, schedule and finance records on this iPhone will be replaced by the backup. The vault stays as it is.": "这台 iPhone 上的便签、日程和记账数据将被备份替换，密码库保持不变。",
    "On this iPhone": "本机",
    "Optic ID": "Optic ID",
    "Passcode": "设备密码",
    "Photo": "照片",
    "Photos": "照片",
    "Plan dates, places and events in one place.": "把日期、地点和日程放在一起规划。",
    "Reminder": "提醒",
    "Remove photo": "移除照片",
    "Repeat master password": "再次输入主密码",
    "Repeat new master password": "再次输入新主密码",
    "Repeats every year": "每年重复",
    "Replace with Backup": "用备份替换",
    "Replace your data?": "替换现有数据？",
    "Reset Vault": "重置密码库",
    "Reset the vault?": "重置密码库？",
    "Restore from Backup": "从备份恢复",
    "Secret Field": "机密字段",
    "Secret fields stay hidden until you tap the eye, and copies of them leave the clipboard after 90 seconds.": "机密字段默认隐藏，点眼睛图标才显示；复制后 90 秒自动从剪贴板清除。",
    "Set a budget in Settings to track it here.": "在设置中设定预算后，这里会显示进度。",
    "Set a passcode on this iPhone to unlock the vault with Face ID.": "为这台 iPhone 设置锁屏密码后，才能用面容 ID 解锁密码库。",
    "Show": "显示",
    "Show password": "显示密码",
    "Tap + to save your first account.": "点 + 保存第一个账号。",
    "Tap to add your first expense": "点一下记第一笔支出",
    "Temporary – not saved": "临时存储，不会保存",
    "Text Field": "文本字段",
    "This file is not a Nook backup": "这个文件不是 Nook 备份",
    "Totals count only records in the selected currency.": "统计只计入所选货币的记录。",
    "Touch ID": "触控 ID",
    "Trip": "行程",
    "Trip Plan – %@": "行程计划 – %@",
    "Trip name": "行程名称",
    "Type": "类型",
    "Unlock": "解锁",
    "Unlock the vault to add an account": "请先解锁密码库再添加账号",
    "Unlock with %@": "使用%@解锁",
    "Unlock your vault": "解锁密码库",
    "Updated %@": "%@更新",
    "Use the original date, such as the date of birth, to see how many years it has been.": "填写最初的日期（例如出生日期），就能看到已经过了多少年。",
    "Value": "内容",
    "Vault is locked": "密码库已锁定",
    "Website": "网站",
    "Write your first note": "写下第一条便签",
    "Wrong master password.": "主密码不正确。",
    "Your name": "你的名字",
}

# key -> (English "one", English "other", Simplified Chinese)
PLURALS = {
    "%lld notes": ("%lld note", "%lld notes", "%lld 条便签"),
    "%lld days": ("%lld day", "%lld days", "%lld 天"),
    "%lld tasks remaining": ("%lld task remaining", "%lld tasks remaining", "还有 %lld 项任务"),
    "%lld events": ("%lld event", "%lld events", "%lld 个日程"),
    "%lld events today": ("%lld event today", "%lld events today", "今天有 %lld 个日程"),
    "%lld years": ("%lld year", "%lld years", "%lld 周年"),
    "In %lld days": ("In %lld day", "In %lld days", "还有 %lld 天"),
    "%lld items could not be decrypted": ("%lld item could not be decrypted", "%lld items could not be decrypted", "有 %lld 项无法解密"),
}

SOURCE_DIR = Path("ios/Nook")
OUTPUT = SOURCE_DIR / "Resources" / "Localizable.xcstrings"
SKIP_FILES = {"SampleData.swift"}  # demo content stays as written

STRING = r'"((?:[^"\\]|\\.)*)"'
CANDIDATES = [
    re.compile(
        r"\b(?:Text|Label|Button|Section|Toggle|DatePicker|Picker|Menu|TextField|LabeledContent|"
        r"ContentUnavailableView|navigationTitle|confirmationDialog|localized:)\(?\s*" + STRING
    ),
    re.compile(r"\b(?:title|label|prompt|message|actionTitle|text):\s*" + STRING),
    re.compile(r"case [^:\n]+:\s*" + STRING + r"\s*$"),
    re.compile(r"\?\?\s*" + STRING),
]
INTERPOLATION = re.compile(r"\\\((?:[^()]|\([^()]*(?:\([^()]*\))*[^()]*\))*\)")
# SF Symbol names, sheet ids, identifiers and strings without lowercase letters ("$", "USD").
NOT_TEXT = re.compile(r"^([a-z0-9]+(\.[a-z0-9]+)*|[a-zA-Z]+-%@|[a-z][A-Za-z]+|[^a-z]*)$")


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def catalog():
    strings = {}
    for key, value in ZH.items():
        strings[key] = {"localizations": {"en": unit(key), "zh-Hans": unit(value)}}
    for key, (one, other, zh) in PLURALS.items():
        strings[key] = {
            "localizations": {
                "en": {"variations": {"plural": {"one": unit(one), "other": unit(other)}}},
                "zh-Hans": unit(zh),
            }
        }
    return {"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}


def normalize(key):
    return re.sub(r"%(\d\$)?(lld|@)", "%@", key)


def missing_keys(root):
    known = {normalize(key) for key in list(ZH) + list(PLURALS)}
    found = {}
    for path in sorted(list((root / SOURCE_DIR).rglob("*.swift")) + list((root / "ios/WidgetShared").rglob("*.swift")) + list((root / "ios/NookWidgets").rglob("*.swift"))):
        if path.name in SKIP_FILES:
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if "systemName" in line and "Text(" not in line and "Label(" not in line:
                continue
            for pattern in CANDIDATES:
                for match in pattern.findall(line):
                    key = INTERPOLATION.sub("%@", match)
                    if NOT_TEXT.match(key) or key in known:
                        continue
                    found.setdefault(key, f"{path.relative_to(root)}:{number}")
    return found


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    root = Path(sys.argv[1])
    ZH.update(json.loads((Path(__file__).parent / "strings-v4.json").read_text(encoding="utf-8")))
    output = root / OUTPUT
    output.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(catalog(), ensure_ascii=False, indent=2) + "\n"
    output.write_text(text, encoding="utf-8")
    widget_keys = ["Nook", "Anniversary", "Today", "Next Event", "Today in Nook", "%lld tasks remaining",
                   "Open Nook to set up widget sharing.", "Next Anniversary", "%lld days",
                   "Open Nook to add an anniversary.", "Your next event and tasks. Details are hidden until you enable them in Nook.",
                   "Anniversary Countdown", "Keep an important date close.", "Nook Shortcuts", "Ask Nook", "Expense", "Note",
                   "Open the assistant, add an expense or write a note."]
    widget_catalog = catalog()
    # Include the literals used by shared layouts and extension metadata, not just
    # the original widget's keys. Normalize Swift interpolation to catalogue keys.
    wanted = set(widget_keys)
    for directory in [root / "ios/WidgetShared", root / "ios/NookWidgets"]:
        for path in directory.rglob("*.swift"):
            for value in re.findall(STRING, path.read_text(encoding="utf-8")):
                normalized = normalize(INTERPOLATION.sub("%@", value))
                wanted.update(key for key in widget_catalog["strings"] if normalize(key) == normalized)
    widget_catalog["strings"] = {key: value for key, value in widget_catalog["strings"].items() if key in wanted}
    widget_output = root / "ios/NookWidgets/Resources/Localizable.xcstrings"
    widget_output.parent.mkdir(parents=True, exist_ok=True)
    widget_output.write_text(json.dumps(widget_catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    json.loads(output.read_text(encoding="utf-8"))
    print(f"wrote {output} with {len(ZH) + len(PLURALS)} keys")
    for key, where in missing_keys(root).items():
        print(f"not translated: {key!r} ({where})")


if __name__ == "__main__":
    main()
