/**
 * Shared helpers for Ohm's Agentforce actions: resolve a bundle by the name a person typed,
 * read the three grades from the saved review, and phrase modeled savings at a request volume.
 * Every figure is modeled from source tokens; the summaries say so.
 */
public with sharing class OhmAgentActions {
    public static final Decimal DEFAULT_REQUESTS_PER_DAY = 300;
    public static final Integer DAYS_PER_YEAR = 365;

    public static List<OhmDTO.ProcessSummaryDTO> fleet() {
        List<OhmDTO.ProcessSummaryDTO> rows = OhmAuditController.getFleet();
        return rows == null ? new List<OhmDTO.ProcessSummaryDTO>() : rows;
    }

    /** Exact label or API name first (any case, with or without the _vN suffix), then a loose contains match. */
    public static OhmDTO.ProcessSummaryDTO resolve(String bundle, List<OhmDTO.ProcessSummaryDTO> rows) {
        if (String.isBlank(bundle) || rows == null) return null;
        String needle = bundle.trim().toLowerCase();
        for (OhmDTO.ProcessSummaryDTO row : rows) {
            if (same(row.label, needle) || same(row.plannerApiName, needle) || same(logicalName(row.plannerApiName), needle)) return row;
        }
        String compact = compactOf(needle);
        if (compact.length() < 3) return null;
        for (OhmDTO.ProcessSummaryDTO row : rows) {
            String label = compactOf(row.label);
            String api = compactOf(logicalName(row.plannerApiName));
            if ((label.length() > 0 && (label.contains(compact) || compact.contains(label))) || (api.length() > 0 && (api.contains(compact) || compact.contains(api)))) return row;
        }
        return null;
    }
    private static Boolean same(String value, String needle) { return value != null && value.trim().toLowerCase() == needle; }
    private static String compactOf(String value) { return value == null ? '' : value.toLowerCase().replaceAll('[^a-z0-9]', ''); }
    public static String logicalName(String apiName) { return apiName == null ? null : apiName.replaceAll('(?i)_v[0-9]+$', ''); }

    public static String displayLabel(OhmDTO.ProcessSummaryDTO row) {
        return String.isNotBlank(row.label) ? row.label : row.plannerApiName;
    }
    public static String availableBundles(List<OhmDTO.ProcessSummaryDTO> rows) {
        List<String> names = new List<String>();
        for (OhmDTO.ProcessSummaryDTO row : rows) names.add(displayLabel(row));
        return names.isEmpty() ? 'No published Agent Script bundles were found.' : 'Available bundles: ' + String.join(names, '; ') + '.';
    }

    /** Input, Output and Calls from the saved review summary. Model Fit stays hidden, as in the app. */
    public static Map<String, String> grades(String reviewJson) {
        Map<String, String> out = new Map<String, String>{ 'INPUT' => 'Unrated', 'OUTPUT' => 'Unrated', 'CALLS' => 'Unrated' };
        if (String.isBlank(reviewJson)) return out;
        try {
            Map<String, Object> summary = (Map<String, Object>) JSON.deserializeUntyped(reviewJson);
            Object categories = summary.get('categories');
            if (categories == null) return out;
            for (Object o : (List<Object>) categories) {
                Map<String, Object> c = (Map<String, Object>) o;
                String id = String.valueOf(c.get('id'));
                if (out.containsKey(id) && c.get('rating') != null) out.put(id, String.valueOf(c.get('rating')));
            }
        } catch (Exception e) {
            // Unreadable summary: keep Unrated rather than invent a grade.
        }
        return out;
    }
    public static Map<String, String> grades(OhmDTO.ProcessSummaryDTO row) { return grades(row == null ? null : row.reviewJson); }
    public static String gradeLine(Map<String, String> g) {
        return 'Input ' + g.get('INPUT') + ', Output ' + g.get('OUTPUT') + ', Calls ' + g.get('CALLS');
    }

    /** value / requests-per-year-the-review-modeled × requests-per-day × 365. */
    public static Decimal scaled(Decimal value, Decimal annualCalls, Decimal requestsPerDay) {
        if (value == null || annualCalls == null || annualCalls <= 0) return null;
        Decimal perDay = (requestsPerDay == null || requestsPerDay <= 0) ? DEFAULT_REQUESTS_PER_DAY : requestsPerDay;
        return value / annualCalls * perDay * DAYS_PER_YEAR;
    }
    public static String energy(Decimal wh) {
        if (wh == null) return 'not modeled';
        if (wh.abs() >= 1000000) return (wh / 1000000).setScale(2) + ' MWh';
        if (wh.abs() >= 1000) return (wh / 1000).setScale(1) + ' kWh';
        return wh.setScale(wh.abs() < 10 ? 2 : 0) + ' Wh';
    }
    public static String mass(Decimal grams) {
        if (grams == null) return 'not modeled';
        return grams.abs() >= 1000 ? (grams / 1000).setScale(1) + ' kg' : grams.setScale(0) + ' g';
    }
    public static String water(Decimal ml) {
        if (ml == null) return 'not modeled';
        return ml.abs() >= 1000 ? (ml / 1000).setScale(1) + ' L' : ml.setScale(0) + ' mL';
    }

    /** Highest modeled savings first. Insertion sort by hand: Apex cannot sort a list of DTOs
     *  without a Comparable wrapper, and List.add(index, ...) rejects an empty target.
     */
    public static List<OhmDTO.ProcessSummaryDTO> rankBySavings(List<OhmDTO.ProcessSummaryDTO> rows) {
        List<OhmDTO.ProcessSummaryDTO> ranked = new List<OhmDTO.ProcessSummaryDTO>();
        for (OhmDTO.ProcessSummaryDTO row : rows) {
            Decimal s = row.savingsWhCentral == null ? -1 : row.savingsWhCentral;
            Integer at = -1;
            for (Integer i = 0; i < ranked.size(); i++) {
                Decimal other = ranked[i].savingsWhCentral == null ? -1 : ranked[i].savingsWhCentral;
                if (s > other) { at = i; break; }
            }
            if (at < 0) { ranked.add(row); } else { ranked.add(at, row); }
        }
        return ranked;
    }

    public static String bundleLine(OhmDTO.ProcessSummaryDTO row, Decimal requestsPerDay) {
        String line = displayLabel(row) + ': ' + gradeLine(grades(row)) + '.';
        if (row.audited != true) return line + ' Not audited yet.';
        Decimal energyYear = scaled(row.energyWhCentral, row.annualCalls, requestsPerDay);
        if (energyYear == null) return line;
        Decimal savingsYear = scaled(row.savingsWhCentral, row.annualCalls, requestsPerDay);
        Decimal share = (row.energyWhCentral != null && row.energyWhCentral > 0 && row.savingsWhCentral != null) ? row.savingsWhCentral / row.energyWhCentral : 0;
        Decimal co2Saved = row.co2eGCentral == null ? null : scaled(row.co2eGCentral, row.annualCalls, requestsPerDay) * share;
        Decimal waterSaved = row.waterMlCentral == null ? null : scaled(row.waterMlCentral, row.annualCalls, requestsPerDay) * share;
        return line + ' Modeled footprint ' + energy(energyYear) + ' a year; applying its recommendations avoids '
            + energy(savingsYear) + ' (' + (share * 100).setScale(0) + '%), ' + mass(co2Saved) + ' CO2e and ' + water(waterSaved) + ' of water.';
    }

    public static String recommendationSummary(OhmDTO.ProcessSummaryDTO row, OhmReviewRecommendationService.RecommendationPage page) {
        String head = displayLabel(row) + ' (' + gradeLine(grades(row)) + '). ';
        if (page == null || page.reviewAvailable != true) return head + 'It has no completed review yet. Start an audit first.';
        if (page.sourceCurrent != true) return head + (String.isNotBlank(page.reason) ? page.reason : 'Its saved review is not current. Start a fresh audit.');
        List<String> parts = new List<String>();
        Integer n = 0;
        for (OhmReviewRecommendationService.Item item : page.items) {
            if (item == null || item.categoryId == 'MODEL' || String.isBlank(item.recommendation)) continue;
            n++;
            String quote = '';
            if (item.evidence != null && !item.evidence.isEmpty() && item.evidence[0] != null && String.isNotBlank(item.evidence[0].quote)) {
                quote = ' Evidence: "' + item.evidence[0].quote.abbreviate(160) + '"';
            }
            parts.add(n + '. [' + item.categoryLabel + ', ' + item.rating + '] Change: ' + item.recommendation
                + ' Keep intact: ' + item.preserve + ' Validate: ' + item.validation + quote);
        }
        if (parts.isEmpty()) return head + 'No changes are recommended in its current saved review.';
        return head + String.join(parts, ' ') + ' Modeled savings if applied: '
            + energy(scaled(row.savingsWhCentral, row.annualCalls, DEFAULT_REQUESTS_PER_DAY)) + ' a year at 300 requests a day.';
    }

    /** Highest-priority current recommendation, optionally within one category. */
    public static OhmReviewRecommendationService.Item pickRecommendation(OhmReviewRecommendationService.RecommendationPage page, String category) {
        if (page == null || page.items == null) return null;
        String wanted = String.isBlank(category) ? null : category.trim().toUpperCase();
        if (wanted == 'CALL') wanted = 'CALLS';
        OhmReviewRecommendationService.Item best = null;
        for (OhmReviewRecommendationService.Item item : page.items) {
            if (item == null || item.categoryId == 'MODEL' || String.isBlank(item.recommendation) || String.isBlank(item.key)) continue;
            if (wanted != null && item.categoryId != wanted) continue;
            if (best == null || (item.rating == 'C' && best.rating != 'C')) best = item;
        }
        return best;
    }

    public static String errorText(Exception e) {
        String message = e.getMessage();
        if (e instanceof AuraHandledException || String.isBlank(message) || message == 'Script-thrown exception') return e.getTypeName();
        return message;
    }
}
