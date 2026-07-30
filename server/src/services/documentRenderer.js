import {
  AlignmentType,
  Document,
  HeadingLevel,
  Packer,
  Paragraph,
  TextRun,
} from 'docx';
import PptxGenJS from 'pptxgenjs';

function cleanText(value, maxLength = 4000) {
  return String(value ?? '')
    .replace(/[\0\u0008\u000B\u000C\u000E-\u001F]/g, '')
    .trim()
    .slice(0, maxLength);
}

function textList(value, maxItems, maxLength) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => cleanText(item, maxLength))
    .filter(Boolean)
    .slice(0, maxItems);
}

function extractJson(text) {
  const raw = String(text ?? '').trim();
  const withoutFence = raw.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  const start = withoutFence.indexOf('{');
  const end = withoutFence.lastIndexOf('}');
  if (start < 0 || end <= start) throw new Error('模型未返回有效的文档结构');
  return JSON.parse(withoutFence.slice(start, end + 1));
}

export function parseDocumentPlan(text, kind, limits = {}) {
  const data = extractJson(text);
  const title = cleanText(data.title, 160) || 'AI 生成文档';
  const subtitle = cleanText(data.subtitle, 240);
  if (kind === 'docx') {
    const maxSections = Math.max(1, Number(limits.maxSections || 20));
    const sections = (Array.isArray(data.sections) ? data.sections : [])
      .slice(0, maxSections)
      .map((section, index) => ({
        heading: cleanText(section?.heading, 160) || `第 ${index + 1} 部分`,
        paragraphs: textList(section?.paragraphs, 12, 5000),
        bullets: textList(section?.bullets, 20, 1000),
      }))
      .filter((section) => section.paragraphs.length > 0 || section.bullets.length > 0);
    if (sections.length === 0) throw new Error('模型未生成可用的 Word 正文');
    return { title, subtitle, sections };
  }

  const maxSlides = Math.max(2, Number(limits.maxSlides || 15));
  const slides = (Array.isArray(data.slides) ? data.slides : [])
    .slice(0, maxSlides)
    .map((slide, index) => ({
      title: cleanText(slide?.title, 140) || `第 ${index + 1} 页`,
      bullets: textList(slide?.bullets, 8, 500),
      body: cleanText(slide?.body, 1800),
      imagePrompt: cleanText(slide?.image_prompt ?? slide?.imagePrompt, 800),
      notes: cleanText(slide?.speaker_notes ?? slide?.notes, 2000),
    }))
    .filter((slide) => slide.bullets.length > 0 || slide.body);
  if (slides.length === 0) throw new Error('模型未生成可用的 PPT 页面');
  return { title, subtitle, slides };
}

export function documentPlanningMessages({ kind, prompt, maxItems, useImages }) {
  const common =
    '你是专业中文文档策划师。只返回一个合法JSON对象，不要Markdown代码块，不要解释。' +
    '内容必须准确、清晰、可直接交付，不要虚构数据；缺少事实时使用明确的待补充占位。';
  if (kind === 'docx') {
    return [
      {
        role: 'system',
        content:
          `${common} JSON格式：{"title":"标题","subtitle":"副标题",` +
          '"sections":[{"heading":"章节标题","paragraphs":["完整段落"],"bullets":["要点"]}]}。' +
          `最多${maxItems}个章节，每段围绕一个主题，避免重复。`,
      },
      { role: 'user', content: prompt },
    ];
  }
  return [
    {
      role: 'system',
      content:
        `${common} JSON格式：{"title":"标题","subtitle":"副标题",` +
        '"slides":[{"title":"页面标题","bullets":["要点"],"body":"补充正文",' +
        '"image_prompt":"配图提示词","speaker_notes":"演讲备注"}]}。' +
        `最多${maxItems}页，每页不超过8个要点。` +
        (useImages
          ? '需要视觉表达的页面提供具体、可生成的image_prompt；纯数据或目录页留空。'
          : '所有image_prompt均留空。'),
    },
    { role: 'user', content: prompt },
  ];
}

export async function renderDocx(plan) {
  const children = [
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { after: 180 },
      children: [new TextRun({ text: plan.title, bold: true, size: 38 })],
    }),
  ];
  if (plan.subtitle) {
    children.push(
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { after: 420 },
        children: [new TextRun({ text: plan.subtitle, color: '5B6573', size: 22 })],
      })
    );
  }
  for (const section of plan.sections) {
    children.push(
      new Paragraph({
        text: section.heading,
        heading: HeadingLevel.HEADING_1,
        spacing: { before: 260, after: 120 },
      })
    );
    for (const paragraph of section.paragraphs) {
      children.push(
        new Paragraph({
          spacing: { line: 360, after: 120 },
          indent: { firstLine: 480 },
          children: [new TextRun({ text: paragraph, size: 22 })],
        })
      );
    }
    for (const bullet of section.bullets) {
      children.push(
        new Paragraph({
          bullet: { level: 0 },
          spacing: { line: 320, after: 70 },
          children: [new TextRun({ text: bullet, size: 21 })],
        })
      );
    }
  }
  const document = new Document({
    creator: 'AI 公益工作台',
    title: plan.title,
    description: plan.subtitle,
    sections: [{ properties: {}, children }],
  });
  return Packer.toBuffer(document);
}

function addPptHeader(slide, title, pageNumber) {
  slide.addText(title, {
    x: 0.65,
    y: 0.42,
    w: 11.9,
    h: 0.55,
    fontFace: 'Microsoft YaHei',
    fontSize: 24,
    bold: true,
    color: '20242A',
    margin: 0,
  });
  slide.addShape('line', {
    x: 0.65,
    y: 1.1,
    w: 12,
    h: 0,
    line: { color: 'DDE3EA', width: 1 },
  });
  slide.addText(String(pageNumber), {
    x: 12.15,
    y: 7.05,
    w: 0.45,
    h: 0.2,
    fontFace: 'Arial',
    fontSize: 9,
    color: '7B8490',
    align: 'right',
    margin: 0,
  });
}

export async function renderPptx(plan, imageBuffers = new Map()) {
  const pptx = new PptxGenJS();
  pptx.layout = 'LAYOUT_WIDE';
  pptx.author = 'AI 公益工作台';
  pptx.subject = plan.subtitle;
  pptx.title = plan.title;
  pptx.company = 'AI 公益工作台';
  pptx.lang = 'zh-CN';
  pptx.theme = {
    headFontFace: 'Microsoft YaHei',
    bodyFontFace: 'Microsoft YaHei',
    lang: 'zh-CN',
  };

  const cover = pptx.addSlide();
  cover.background = { color: 'F3F5F7' };
  cover.addShape('rect', {
    x: 0,
    y: 0,
    w: 0.18,
    h: 7.5,
    line: { color: '3978D3', transparency: 100 },
    fill: { color: '3978D3' },
  });
  cover.addText(plan.title, {
    x: 1.05,
    y: 2.25,
    w: 11.2,
    h: 1.25,
    fontFace: 'Microsoft YaHei',
    fontSize: 34,
    bold: true,
    color: '20242A',
    breakLine: false,
    margin: 0,
  });
  if (plan.subtitle) {
    cover.addText(plan.subtitle, {
      x: 1.08,
      y: 3.72,
      w: 10.8,
      h: 0.8,
      fontFace: 'Microsoft YaHei',
      fontSize: 17,
      color: '526171',
      margin: 0,
    });
  }

  plan.slides.forEach((item, index) => {
    const slide = pptx.addSlide();
    slide.background = { color: 'F8F9FB' };
    addPptHeader(slide, item.title, index + 2);
    const image = imageBuffers.get(index);
    const textWidth = image ? 6.65 : 11.75;
    const runs = item.bullets.map((text) => ({
      text,
      options: { bullet: { indent: 18 }, hanging: 4, breakLine: true },
    }));
    if (item.body) runs.push({ text: item.body, options: { breakLine: true } });
    slide.addText(runs.length > 0 ? runs : [{ text: '内容待补充', options: {} }], {
      x: 0.78,
      y: 1.38,
      w: textWidth,
      h: 5.25,
      fontFace: 'Microsoft YaHei',
      fontSize: 18,
      color: '303640',
      breakLine: false,
      valign: 'top',
      margin: 0.08,
      paraSpaceAfterPt: 12,
      fit: 'shrink',
    });
    if (image) {
      slide.addImage({
        data: `data:image/png;base64,${image.toString('base64')}`,
        x: 7.75,
        y: 1.45,
        w: 4.85,
        h: 4.85,
        sizing: 'contain',
      });
    }
    if (item.notes && typeof slide.addNotes === 'function') slide.addNotes(item.notes);
  });
  const output = await pptx.write({ outputType: 'nodebuffer' });
  return Buffer.isBuffer(output) ? output : Buffer.from(output);
}

export function safeArtifactTitle(value, fallback = 'AI文档') {
  const cleaned = cleanText(value, 80)
    .replace(/[<>:"/\\|?*\u0000-\u001F]/g, '_')
    .replace(/[. ]+$/, '');
  return cleaned || fallback;
}

