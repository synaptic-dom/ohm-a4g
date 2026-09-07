/** Parses bounded, retrieved source without executing or rewriting its instruction DSL. */
public with sharing class OhmSourceParser {
    public static final String METADATA_NS = 'http://soap.sforce.com/2006/04/metadata';
    public static final Integer MAX_SOURCE_CHARS = 262144;
    public static final Integer MAX_ARCHIVE_BYTES = 1048576;
    public static final Integer MAX_ENTRY_BYTES = 262144;
    public static final Integer MAX_ARCHIVE_ENTRIES = 200;
    public class SourceParseException extends Exception {}

    public class AgentScript {
        public String developerName;
        public String systemInstructions = '';
        public Map<String, String> topics = new Map<String, String>();
    }
    public class PublishedScript {
        public String script;
        public String path;
        public String target;
    }
    public class PromptTemplate {
        public String apiName;
        public String instructions;
        public String boundModel;
        public String versionIdentifier;
    }
    public class LegacyPlugin {
        public String apiName;
        public String instructions;
    }

    /** Inspect sizes before decompression; preserve every byte of supported source files. */
    public static Map<String, String> readArchive(Blob archive) {
        if (archive == null || archive.size() == 0 || archive.size() > MAX_ARCHIVE_BYTES) {
            throw new SourceParseException('Metadata ZIP is empty or exceeds the 1 MiB retrieval limit.');
        }
        Compression.ZipReader reader = new Compression.ZipReader(archive);
        List<Compression.ZipEntry> entries = reader.getEntries();
        if (entries.size() > MAX_ARCHIVE_ENTRIES) {
            throw new SourceParseException('Metadata ZIP exceeds the 200-entry retrieval limit.');
        }
        Set<String> seen = new Set<String>();
        Map<String, String> files = new Map<String, String>();
        Long total = 0;
        for (Compression.ZipEntry entry : entries) {
            String path = entry.getName();
            if (String.isBlank(path) || path.startsWith('/') || path.contains('\\')
                || path.split('/').contains('..') || seen.contains(path)) {
                throw new SourceParseException('Metadata ZIP contains an invalid or duplicated path.');
            }
            seen.add(path);
            if (path.endsWith('/') || !isSourceFile(path)) { continue; }
            Long size = entry.getUncompressedSize();
            if (size == null || size < 0 || size > MAX_ENTRY_BYTES) {
                throw new SourceParseException('Source entry exceeds the 256 KiB retrieval limit: ' + path);
            }
            total += size;
            if (total > MAX_ARCHIVE_BYTES) {
                throw new SourceParseException('Uncompressed source exceeds the 1 MiB retrieval limit.');
            }
            Blob content = reader.extract(entry);
            if (content.size() != size || content.size() > MAX_ENTRY_BYTES) {
                throw new SourceParseException('Source entry size did not match ZIP metadata: ' + path);
            }
            files.put(path, content.toString());
        }
        return files;
    }

    private static Boolean isSourceFile(String path) {
        String p = '/' + path;
        return (p.contains('/aiAuthoringBundles/') && (p.endsWith('.agent') || p.endsWith('.bundle-meta.xml')))
            || (p.contains('/genAiPromptTemplates/') && (p.endsWith('.genAiPromptTemplate') || p.endsWith('.genAiPromptTemplate-meta.xml')))
            || (p.contains('/genAiPlugins/') && (p.endsWith('.genAiPlugin') || p.endsWith('.genAiPlugin-meta.xml')));
    }

    /** ZIP directory names can be unversioned. The descriptor target supplies version identity. */
    public static PublishedScript publishedScript(Map<String, String> files, String expectedTarget) {
        PublishedScript found;
        for (String path : files.keySet()) {
            if (!('/' + path).contains('/aiAuthoringBundles/') || !path.endsWith('.bundle-meta.xml')) { continue; }
            Dom.XmlNode root = xmlRoot(files.get(path), 'AiAuthoringBundle');
            if (childText(root, 'target') != expectedTarget) { continue; }
            if (found != null) { throw new SourceParseException('Multiple authoring bundles match the selected publication.'); }
            if (childText(root, 'bundleType') != 'AGENT') {
                throw new SourceParseException('The published authoring bundle is not an AGENT bundle.');
            }
            String scriptPath = path.substring(0, path.length() - '.bundle-meta.xml'.length()) + '.agent';
            if (!files.containsKey(scriptPath)) {
                throw new SourceParseException('Published authoring bundle has no matching Agent Script file.');
            }
            found = new PublishedScript();
            found.script = files.get(scriptPath); found.path = scriptPath; found.target = expectedTarget;
        }
        return found;
    }

    public static AgentScript agentScript(String source, String expectedDeveloperName) {
        checkSource(source);
        // Match Python's universal-newline file reading; do not otherwise normalize source text.
        List<String> lines = source.replace('\r\n', '\n').replace('\r', '\n').split('\n', -1);
        AgentScript result = new AgentScript();
        Boolean systemSeen = false;
        for (Integer i = 0; i < lines.size(); i++) {
            if (lines[i].startsWith(' ') || lines[i].startsWith('\t') || lines[i].startsWith('#')) { continue; }
            Matcher header = Pattern.compile('^(config|system|start_agent\\s+[A-Za-z_][A-Za-z0-9_]*|subagent\\s+[A-Za-z_][A-Za-z0-9_]*)\\s*:\\s*$').matcher(lines[i]);
            if (!header.matches()) { continue; }
            String name = header.group(1);
            Integer endIndex = i + 1;
            while (endIndex < lines.size()) {
                String line = lines[endIndex];
                if (String.isNotBlank(line) && !line.startsWith(' ') && !line.startsWith('\t') && !line.startsWith('#')) { break; }
                endIndex++;
            }
            List<String> block = new List<String>();
            for (Integer j = i + 1; j < endIndex; j++) { block.add(lines[j]); }
            if (name == 'config') {
                if (result.developerName != null) { throw new SourceParseException('Duplicate Agent Script config.'); }
                result.developerName = configDeveloperName(block);
            } else {
                String text = instructionsInBlock(block);
                if (name == 'system') {
                    if (systemSeen) { throw new SourceParseException('Duplicate system instruction section.'); }
                    systemSeen = true; result.systemInstructions = text == null ? '' : text;
                } else {
                    String topic = name.split('\\s+')[1];
                    if (text == null) { throw new SourceParseException('No instruction source for ' + topic); }
                    if (result.topics.containsKey(topic)) { throw new SourceParseException('Duplicate Agent Script topic: ' + topic); }
                    result.topics.put(topic, text);
                }
            }
            i = endIndex - 1;
        }
        if (String.isBlank(result.developerName) || result.developerName != expectedDeveloperName) {
            throw new SourceParseException('Agent Script developer_name does not match the selected planner.');
        }
        if (result.topics.isEmpty()) { throw new SourceParseException('No supported Agent Script topics found.'); }
        return result;
    }

    private static String configDeveloperName(List<String> lines) {
        String result;
        for (String line : lines) {
            Matcher m = Pattern.compile('^\\s*developer_name\\s*:\\s*(.*?)\\s*$').matcher(line);
            if (!m.matches()) { continue; }
            if (result != null) { throw new SourceParseException('Duplicate developer_name in Agent Script.'); }
            result = quoted(m.group(1));
        }
        return result;
    }

    private static String instructionsInBlock(List<String> lines) {
        List<String> found = new List<String>();
        for (Integer i = 0; i < lines.size(); i++) {
            Matcher m = Pattern.compile('^(\\s*)instructions\\s*:\\s*(.*?)\\s*$').matcher(lines[i]);
            if (!m.matches()) { continue; }
            if (m.group(1).contains('\t')) { throw new SourceParseException('Tab indentation is unsupported in instruction blocks.'); }
            String value = m.group(2);
            if (value.startsWith('"') || value.startsWith('\'')) { found.add(quoted(value)); continue; }
            if (value != '|' && value != '->') { throw new SourceParseException('Unsupported instruction expression: ' + value); }
            Integer indent = m.group(1).length();
            List<String> following = new List<String>();
            Integer j = i + 1;
            for (; j < lines.size(); j++) {
                if (String.isNotBlank(lines[j]) && indentation(lines[j]) <= indent) { break; }
                following.add(lines[j]);
            }
            String text = dedent(following);
            if (String.isBlank(text)) { throw new SourceParseException('Empty indented instruction block.'); }
            found.add(text);
            i = j - 1;
        }
        return found.isEmpty() ? null : String.join(found, '\n\n');
    }

    private static String quoted(String value) {
        if (value.startsWith('"')) {
            try {
                Object decoded = JSON.deserializeUntyped(value);
                if (decoded instanceof String) { return (String)decoded; }
            } catch (Exception ex) { /* Return a source-format error without exposing prompt text. */ }
            throw new SourceParseException('Unsupported double-quoted instruction format.');
        }
        if (value.startsWith('\'') && value.endsWith('\'') && value.length() >= 2) {
            return value.substring(1, value.length() - 1).replace('\'\'', '\'');
        }
        throw new SourceParseException('Unsupported or unclosed quoted source value.');
    }

    private static Integer indentation(String line) {
        Integer count = 0;
        while (count < line.length()) {
            String character = line.substring(count, count + 1);
            if (character == '\t') { throw new SourceParseException('Tab indentation is unsupported in instruction blocks.'); }
            if (character != ' ') { break; }
            count++;
        }
        return count;
    }

    private static String dedent(List<String> lines) {
        Integer common;
        for (String line : lines) {
            if (String.isBlank(line)) { continue; }
            Integer indent = indentation(line);
            common = common == null ? indent : Math.min(common, indent);
        }
        if (common == null) { return ''; }
        List<String> result = new List<String>();
        for (String line : lines) { result.add(String.isBlank(line) ? '' : line.substring(common)); }
        return String.join(result, '\n').replaceFirst('[\\s\\u00A0]+$', '');
    }

    public static PromptTemplate promptTemplate(String source, String expectedApiName) {
        Dom.XmlNode root = xmlRoot(source, 'GenAiPromptTemplate');
        String apiName = childText(root, 'developerName');
        if (String.isNotBlank(apiName) && apiName != expectedApiName) { throw new SourceParseException('Prompt template API name mismatch.'); }
        String active = childText(root, 'activeVersionIdentifier');
        if (String.isBlank(active)) { throw new SourceParseException('Prompt template has no active version identifier.'); }
        List<Dom.XmlNode> matches = new List<Dom.XmlNode>();
        for (Dom.XmlNode version : children(root, 'templateVersions')) {
            if (childText(version, 'versionIdentifier') == active) { matches.add(version); }
        }
        if (matches.size() != 1) { throw new SourceParseException('Cannot resolve exactly one active prompt template version.'); }
        Dom.XmlNode version = matches[0];
        if (childText(version, 'status') != 'Published' || child(version, 'content') == null) {
            throw new SourceParseException('Active prompt template version is unpublished or has no content.');
        }
        PromptTemplate result = new PromptTemplate();
        result.apiName = expectedApiName; result.versionIdentifier = active;
        result.instructions = childText(version, 'content'); result.boundModel = childText(version, 'primaryModel');
        return result;
    }

    public static LegacyPlugin legacyPlugin(String source, String expectedApiName) {
        Dom.XmlNode root = xmlRoot(source, 'GenAiPlugin');
        String apiName = childText(root, 'developerName');
        if (String.isNotBlank(apiName) && apiName != expectedApiName) { throw new SourceParseException('Legacy plugin API name mismatch.'); }
        List<String> instructions = new List<String>();
        for (Dom.XmlNode instruction : children(root, 'genAiPluginInstructions')) {
            String text = childText(instruction, 'description');
            if (String.isBlank(text)) { throw new SourceParseException('Legacy plugin has an empty instruction.'); }
            instructions.add(text);
        }
        if (instructions.isEmpty()) { throw new SourceParseException('Legacy plugin has no nested instructions.'); }
        LegacyPlugin result = new LegacyPlugin(); result.apiName = expectedApiName;
        result.instructions = String.join(instructions, '\n\n'); return result;
    }

    public static Dom.XmlNode xmlRoot(String source, String expectedName) {
        checkSource(source);
        if (source.toUpperCase().contains('<!DOCTYPE')) { throw new SourceParseException('Document type declarations are unsupported in source metadata.'); }
        Dom.Document document = new Dom.Document(); document.load(source);
        Dom.XmlNode root = document.getRootElement();
        if (root.getName() != expectedName || root.getNamespace() != METADATA_NS) {
            throw new SourceParseException('Unexpected metadata XML root: ' + expectedName);
        }
        return root;
    }
    public static Dom.XmlNode child(Dom.XmlNode node, String name) {
        return node == null ? null : node.getChildElement(name, METADATA_NS);
    }
    public static String childText(Dom.XmlNode node, String name) {
        Dom.XmlNode value = child(node, name); return value == null ? null : value.getText();
    }
    public static List<Dom.XmlNode> children(Dom.XmlNode node, String name) {
        List<Dom.XmlNode> result = new List<Dom.XmlNode>();
        if (node != null) {
            for (Dom.XmlNode item : node.getChildElements()) {
                if (item.getName() == name && item.getNamespace() == METADATA_NS) { result.add(item); }
            }
        }
        return result;
    }
    private static void checkSource(String source) {
        if (source == null || source.length() > MAX_SOURCE_CHARS) {
            throw new SourceParseException('Source is missing or exceeds the 262144-character parser limit.');
        }
    }
}
