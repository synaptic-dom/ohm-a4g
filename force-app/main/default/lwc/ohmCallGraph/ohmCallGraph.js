import { LightningElement, api } from 'lwc';
import { SIGNAL_LABELS } from 'c/ohmConstants';

/**
 * ohmCallGraph — the agent → topic → action call graph (SPEC §2.2, Idea 2).
 *
 * Draws the tree FROM NodeDTO.parentId (never queries linkage): agent at top,
 * topics below it, actions below their topic. Inline SVG for the connector edges
 * (CSP blocks CDNs / external libs); nodes are real focusable <button>s overlaid
 * on the SVG so they are keyboard-accessible (Enter/Space select natively) and
 * carry aria-labels that name status in words — no meaning by colour alone.
 *
 * Wasteful nodes get the amber/hot filament outline+glow; clean nodes stay quiet.
 * Clicking (or Enter/Space on) a node fires `selectnode {detail:{nodeId}}`; the
 * parent passes `selectedNodeId` back down for the selected ring.
 *
 * Layout is a tidy bottom-up tree: leaf actions get columns, each topic centres
 * over its actions, the agent centres over the topics. Small fixtures (agent → 1
 * topic → 0–2 actions) read cleanly; wide graphs scroll inside their own box.
 */
const NODE_W = 184;
const NODE_H = 74;
const COL_GAP = 44;
const ROW_STEP = 132;
const PAD_X = 28;
const PAD_Y = 20;
const SLOT_W = NODE_W + COL_GAP;

export default class OhmCallGraph extends LightningElement {
    @api nodes = [];
    @api selectedNodeId;
    @api calmMode = false;

    get hostClass() {
        return 'ohm-graph';
    }

    get hasNodes() {
        return Array.isArray(this.nodes) && this.nodes.length > 0;
    }

    /**
     * The full drawable model: canvas size, viewBox, SVG edge paths, and the
     * positioned node buttons. Recomputed per render (fixtures are tiny).
     */
    get model() {
        const nodes = Array.isArray(this.nodes) ? this.nodes : [];
        const byId = {};
        nodes.forEach((n) => {
            byId[n.id] = n;
        });

        const agent =
            nodes.find((n) => n.nodeType === 'Agent') ||
            nodes.find((n) => !n.parentId) ||
            null;
        const topics = nodes.filter((n) => n.nodeType === 'Topic');
        const actions = nodes.filter((n) => n.nodeType === 'Action');

        // group actions under their parent topic; anything else is an orphan
        const actionsByTopic = {};
        const orphanActions = [];
        actions.forEach((a) => {
            const parent = byId[a.parentId];
            if (parent && parent.nodeType === 'Topic') {
                (actionsByTopic[parent.id] =
                    actionsByTopic[parent.id] || []).push(a);
            } else {
                orphanActions.push(a);
            }
        });

        // assign leaf columns (fractional centres bubble up to parents)
        const colOf = {};
        let col = 0;
        topics.forEach((t) => {
            const acts = actionsByTopic[t.id] || [];
            if (acts.length) {
                const cols = [];
                acts.forEach((a) => {
                    colOf[a.id] = col;
                    cols.push(col);
                    col += 1;
                });
                colOf[t.id] = cols.reduce((s, c) => s + c, 0) / cols.length;
            } else {
                colOf[t.id] = col;
                col += 1;
            }
        });
        orphanActions.forEach((a) => {
            colOf[a.id] = col;
            col += 1;
        });
        if (agent) {
            const topicCols = topics.map((t) => colOf[t.id]);
            colOf[agent.id] = topicCols.length
                ? topicCols.reduce((s, c) => s + c, 0) / topicCols.length
                : col > 0
                ? (col - 1) / 2
                : 0;
        }
        const totalCols = Math.max(col, 1);

        // row Y per present tier
        const hasTopics = topics.length > 0;
        const hasActions = actions.length > 0;
        const agentY = PAD_Y;
        const topicY = agentY + ROW_STEP;
        const actionY = topicY + ROW_STEP;

        const leftOf = (c) => PAD_X + c * SLOT_W;
        const centerXOf = (c) => leftOf(c) + NODE_W / 2;
        const yOf = (type) => {
            if (type === 'Agent') {
                return agentY;
            }
            if (type === 'Topic') {
                return topicY;
            }
            return actionY;
        };

        const width = PAD_X * 2 + (totalCols - 1) * SLOT_W + NODE_W;
        let lowest = agentY;
        if (hasTopics) {
            lowest = topicY;
        }
        if (hasActions) {
            lowest = actionY;
        }
        const height = lowest + NODE_H + PAD_Y;

        // edges: agent → topics, topic → its actions, agent → orphan actions
        const edges = [];
        const addEdge = (parent, child) => {
            if (!parent || !child) {
                return;
            }
            const px = centerXOf(colOf[parent.id]);
            const py = yOf(parent.nodeType) + NODE_H;
            const cx = centerXOf(colOf[child.id]);
            const cy = yOf(child.nodeType);
            const midY = (py + cy) / 2;
            edges.push({
                id: `${parent.id}->${child.id}`,
                d: `M ${px} ${py} C ${px} ${midY} ${cx} ${midY} ${cx} ${cy}`,
                cssClass: child.wasteful
                    ? 'ohm-graph__edge ohm-graph__edge--waste'
                    : 'ohm-graph__edge'
            });
        };
        topics.forEach((t) => {
            addEdge(agent, t);
            (actionsByTopic[t.id] || []).forEach((a) => addEdge(t, a));
        });
        orphanActions.forEach((a) => addEdge(agent, a));

        // node buttons
        const nodeButtons = nodes
            .filter((n) => colOf[n.id] !== undefined)
            .map((n) => {
                const left = leftOf(colOf[n.id]);
                const top = yOf(n.nodeType);
                const selected = n.id === this.selectedNodeId;
                const statusWord = n.wasteful
                    ? `finding to review${
                          n.signalType && SIGNAL_LABELS[n.signalType]
                              ? ' — ' + SIGNAL_LABELS[n.signalType]
                              : ''
                      }`
                    : 'no findings in available evidence';
                let cssClass = 'ohm-graph__node';
                cssClass += n.wasteful
                    ? ' ohm-graph__node--waste'
                    : ' ohm-graph__node--clean';
                if (selected) {
                    cssClass += ' ohm-graph__node--selected';
                }
                cssClass += ` ohm-graph__node--${(
                    n.nodeType || 'node'
                ).toLowerCase()}`;
                return {
                    id: n.id,
                    label: n.label || n.apiName || '(unnamed)',
                    typeTag: n.nodeType,
                    wasteful: !!n.wasteful,
                    selected,
                    ariaPressed: selected ? 'true' : 'false',
                    ariaLabel: `${n.label || n.apiName || 'node'}, ${
                        n.nodeType
                    }, ${statusWord}`,
                    style: `left:${left}px;top:${top}px;width:${NODE_W}px;min-height:${NODE_H}px;`,
                    cssClass
                };
            });

        return {
            width,
            height,
            viewBox: `0 0 ${width} ${height}`,
            canvasStyle: `width:${width}px;height:${height}px;`,
            edges,
            nodeButtons
        };
    }

    handleNodeClick(event) {
        const nodeId = event.currentTarget.dataset.nodeId;
        if (!nodeId) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('selectnode', {
                detail: { nodeId },
                bubbles: true,
                composed: true
            })
        );
    }
}
