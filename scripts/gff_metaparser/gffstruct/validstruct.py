# valid structures

import sys

from collections import defaultdict

from .rules import *

# VALID STRUCTURES class

class ValidStructures:
  KNOWN_RULES = [
    AliasRule,
    IgnoreRule,
    ValidRule,
    ValidIfRule,
    FixRule,
    ForceFixRule,
    SubRule,
    ForceSubRule,
    SetRule,
  ]

  def __init__(self, config):
    self.rule_factories = { r.NAME.lower().strip() : r for r in self.KNOWN_RULES }

    # prepare factories from KNOWN_RULES
    self.config = config
    self.load_conf()

    # propagate aliases to rules
    aliasCls = 'alias' in self.rule_factories and self.rule_factories['alias'] or None

    # filling patterns to match to
    self.const_patterns = defaultdict(list)
    self.regex_patterns = list()

    for name in self.rule_factories:
      factory = self.rule_factories[name]
      factory.mature_regex(aliasCls)
      const_patterns = factory.const_patterns()
      there_were = frozenset(const_patterns.keys()) & frozenset(self.const_patterns.keys())
      if there_were:
         print("already seen pattern for %s" % (", ".join(there_were)) ,file=sys.stderr)
      for pat, rules in const_patterns.items():
        self.const_patterns[pat] += rules
      # regex_pattersn are checked dynamically for multiple hits
      self.regex_patterns += factory.regex_patterns()

  def load_conf(self):
    if not self.config:
      return
    for lineno, raw in enumerate(self.config, start=1):
      (nocmt, *_) = raw.partition('#')
      nocmt = nocmt.strip()
      if not nocmt:
        continue
      pattern, name, *actions = nocmt.split(maxsplit=2)
      self.add_rule(name, pattern, actions, lineno)

  def add_rule(self, name_raw, pattern, actions, lineno):
    name = name_raw.lower().strip()
    if name not in self.rule_factories:
      print("can't load unknown rule %s (raw: %s) at line %s" % (name, name_raw, lineno), file = sys.stderr)
      return
    factory = self.rule_factories[name]
    rule = factory(pattern, actions, lineno)

  def process(self, struct):
    tag_raw = struct.tag
    tag = tag_raw.lower().strip()
    matched_rules = []

    if tag in self.const_patterns:
      matched_rules += list(map(lambda x: MatchedRuleCtx(x), self.const_patterns[tag]))
    # or stop if there's a constant match
    for it in self.regex_patterns:
      matching = it.re.match(tag)
      if matching:
        matched_rules.append(MatchedRuleCtx(it.rule, matching))

    if matched_rules:
      for wrp in matched_rules:
        wrp.rule.process(struct, re_context = wrp.ctx)
    else:
      UnseenRule.process(struct, noconfig = (self.config == None))

    # return ???
  class Structure:
    def __init__(self, tag = ""):
      self.tag = tag

class MatchedRuleCtx:
  def __init__(self, rule, ctx = None):
    self.rule = rule
    self.ctx = ctx

