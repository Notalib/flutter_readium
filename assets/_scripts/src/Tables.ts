// Responsive table styles applied to tables with headers
export function initResponsiveTables(): void {
  let tables = Array.from(document.querySelectorAll('table'));

  // Filter out tables with class 'docx-table' or 'transparent-table'
  tables = tables.filter(
    (table) => !table.classList.contains('docx-table') && !table.classList.contains('transparent-table') && !table.classList.contains('plain-table'),
  );

  // If the tables array is empty or null, do nothing and return early
  if (!tables || tables.length === 0) {
    return;
  }

  tables.forEach((table) => {
    // Identify if nonstandard table
    // All steps created for nonstandard tables have been created with copilot and had minor edits
    if (_checkIfMostlyEmptyTable(table)) {
      return;
    }

    const theadThCount = table.querySelectorAll('thead th').length;
    const tbodyTrs = table.querySelectorAll('tbody tr');
    const isNonStandardTable = theadThCount === 1 && Array.from(tbodyTrs).every((tr) => tr.querySelectorAll('td').length === 2);

    if (isNonStandardTable) {
      // If special table if it has headlines in the columns or first row
      const firstTbodyTr = tbodyTrs[0];
      const firstRowCells = firstTbodyTr.querySelectorAll('td');
      const hasStrongOrHeadlineTags = Array.from(firstRowCells).every(
        (td) => td.querySelector('strong') || Array.from({ length: 6 }, (_, i) => td.querySelector(`h${i + 1}`)).some((element) => element !== null),
      );

      // If headlines in the first row, make it a plain table
      if (hasStrongOrHeadlineTags) {
        table.classList.add('plain-table');
        return;
      }
      _flattenTable(table);
    }

    _transformResponsiveTable(table);
  });
}

function _transformResponsiveTable(table: HTMLTableElement) {
  let tableHeaderRow: HTMLTableRowElement | null = null;
  let tableHeaders: HTMLTableCellElement[] = [];

  // if the table has a table head
  if (table.tHead) {
    tableHeaderRow = table.tHead.rows[0];
    tableHeaders = Array.from(tableHeaderRow.cells);
  } else {
    // get the first row, whether it's in a tbody or not
    const firstRow = table.rows[0];
    if (firstRow && firstRow.querySelector('th, h1, h2, h3, h4, h5, h6, strong')) {
      tableHeaderRow = firstRow;
      tableHeaders = Array.from(firstRow.cells);
      table.classList.add('has-first-row-headers');
    }
  }

  // if the table has headers
  if (tableHeaders.length) {
    table.classList.add('has-header');

    const headers = tableHeaders.map((headerCell) => {
      let header = headerCell.textContent?.trim() || '';
      if (header.length) {
        header += ':'; // append colon to non-empty headers
      }
      return header;
    });

    Array.from(table.rows)
      .filter((row) => row !== tableHeaderRow)
      .forEach((row) => {
        Array.from(row.cells).forEach((cell, index) => {
          cell.setAttribute('data-th', headers[index] || '');
        });

        if (!row.cells[0].getAttribute('data-th')) {
          row.cells[0].classList.add('mobile-header');
          // Changing the first cell to an h6 from strong to make text color styling possible on ios
          const h6 = document.createElement('h6');
          h6.textContent = row.cells[0].textContent;
          row.cells[0].textContent = '';
          row.cells[0].appendChild(h6);
        }
      });
  }
}

function _checkIfMostlyEmptyTable(table: HTMLTableElement) {
  let emptyCells = 0;
  let nonEmptyCells = 0;

  //  Iterate through all rows and cells
  table.querySelectorAll('tr').forEach((row) => {
    row.querySelectorAll('td').forEach((cell) => {
      // Check if cell is empty
      if (cell.textContent.trim() === '') {
        emptyCells++;
      } else {
        nonEmptyCells++;
      }
    });
  });

  // Compare counts and modify table if necessary
  if (emptyCells > nonEmptyCells) {
    table.classList.add('plain-table');
    return true;
  }
  return false;
}

function _flattenTable(table: HTMLTableElement) {
  // If headlines in the columns, transform the table so that the script following can transform it to match the other tables correctly
  const theadThText = table.querySelector('thead th').textContent;
  const tbodyTds = Array.from(table.querySelectorAll('tbody td'));

  // Clear the table and start the transformation
  table.innerHTML = '';

  const newTbody = document.createElement('tbody');
  const headerRow = document.createElement('tr');
  const contentRow = document.createElement('tr');

  headerRow.innerHTML = '<td>&#160;</td>'; // Initial empty cell
  contentRow.innerHTML = `<td>${theadThText}</td>`; // Thead text becomes the first cell in the second row

  tbodyTds.forEach((td, index) => {
    if (index % 2 === 0) {
      // Even index, header row
      const headerCell = document.createElement('td');
      headerCell.innerHTML = `<h3>${td.textContent}</h3>`;
      headerRow.appendChild(headerCell);
    } else {
      // Odd index, content row
      const contentCell = document.createElement('td');
      // Directly append the content to the contentCell
      Array.from(td.childNodes).forEach((child) => contentCell.appendChild(child.cloneNode(true)));
      contentRow.appendChild(contentCell);
    }
  });

  newTbody.appendChild(headerRow);
  newTbody.appendChild(contentRow);
  table.appendChild(newTbody);

  return table;
}
