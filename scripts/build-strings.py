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
    "%lld accounts · %lld categories": "%lld 个账号 · %lld 个分类",
    "%@ left this month": "本月还剩 %@",
    "%@ of %@": "已用 %1$@ / 预算 %2$@",
    "%lld open": "%lld 项未完成",
    "+%lld more": "还有 %lld 项",
    "About": "关于",
    "Account": "账号",
    "Account name copied": "已复制账号名",
    "Accounts": "账号",
    "Accounts arrive with vault encryption": "账号功能将随密码库加密一起推出",
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
    "Attachments": "附件",
    "Back to this week": "回到本周",
    "Backup could not be prepared": "备份文件生成失败",
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
    "Copy account name": "复制账号名",
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
    "Exports notes, schedule and finance records as a JSON file. Vault items are never included.":
        "将便签、日程和记账数据导出为 JSON 文件。密码库内容不会被导出。",
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
    "Item not found": "找不到该项目",
    "Life": "生活",
    "Light": "浅色",
    "Local profile · no account needed": "本地资料 · 无需账号",
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
    "Not stored in this preview": "演示版不保存密码",
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
    "Passwords will be stored with end-to-end encryption in a later version. Nothing secret is saved yet.":
        "后续版本会用端到端加密保存密码，目前不会保存任何机密信息。",
    "Personal": "个人",
    "Photo of Mt. Fuji": "富士山照片",
    "Pin": "置顶",
    "Pinned": "已置顶",
    "Preparing backup…": "正在准备备份…",
    "Preview": "演示",
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
    "Sample data in memory": "示例数据（仅在内存中）",
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
    "Upload File": "上传文件",
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
}

# key -> (English "one", English "other", Simplified Chinese)
PLURALS = {
    "%lld events": ("%lld event", "%lld events", "%lld 个日程"),
    "%lld events today": ("%lld event today", "%lld events today", "今天有 %lld 个日程"),
    "%lld years": ("%lld year", "%lld years", "%lld 周年"),
    "In %lld days": ("In %lld day", "In %lld days", "还有 %lld 天"),
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
        strings[key] = {"localizations": {"zh-Hans": unit(value)}}
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
    for path in sorted((root / SOURCE_DIR).rglob("*.swift")):
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
    output = root / OUTPUT
    output.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(catalog(), ensure_ascii=False, indent=2) + "\n"
    output.write_text(text, encoding="utf-8")
    json.loads(output.read_text(encoding="utf-8"))
    print(f"wrote {output} with {len(ZH) + len(PLURALS)} keys")
    for key, where in missing_keys(root).items():
        print(f"not translated: {key!r} ({where})")


if __name__ == "__main__":
    main()
